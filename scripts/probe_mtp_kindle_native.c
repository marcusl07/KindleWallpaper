#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <libmtp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct FolderPath {
    uint32_t folder_id;
    uint32_t parent_id;
    uint32_t storage_id;
    char *name;
    char *path;
    struct FolderPath *next;
} FolderPath;

static int equals_ci(const char *a, const char *b) {
    if (a == NULL || b == NULL) {
        return 0;
    }

    while (*a != '\0' && *b != '\0') {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) {
            return 0;
        }
        a++;
        b++;
    }

    return *a == '\0' && *b == '\0';
}

static int has_ci_path_component(const char *path, const char *component) {
    if (path == NULL || component == NULL) {
        return 0;
    }

    const char *cursor = path;
    while (*cursor != '\0') {
        while (*cursor == '/') {
            cursor++;
        }

        const char *start = cursor;
        while (*cursor != '\0' && *cursor != '/') {
            cursor++;
        }

        size_t len = (size_t)(cursor - start);
        size_t component_len = strlen(component);
        if (len == component_len) {
            int match = 1;
            for (size_t i = 0; i < len; i++) {
                if (tolower((unsigned char)start[i]) != tolower((unsigned char)component[i])) {
                    match = 0;
                    break;
                }
            }
            if (match) {
                return 1;
            }
        }
    }

    return 0;
}

static char *copy_string(const char *value) {
    if (value == NULL) {
        return NULL;
    }

    size_t length = strlen(value);
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }

    memcpy(copy, value, length + 1);
    return copy;
}

static char *join_path(const char *parent, const char *name) {
    const char *safe_name = name == NULL ? "<unnamed>" : name;
    if (parent == NULL || strcmp(parent, "/") == 0) {
        size_t length = strlen(safe_name) + 2;
        char *joined = malloc(length);
        if (joined == NULL) {
            return NULL;
        }
        snprintf(joined, length, "/%s", safe_name);
        return joined;
    }

    size_t length = strlen(parent) + strlen(safe_name) + 2;
    char *joined = malloc(length);
    if (joined == NULL) {
        return NULL;
    }
    snprintf(joined, length, "%s/%s", parent, safe_name);
    return joined;
}

static void free_folder_paths(FolderPath *paths) {
    while (paths != NULL) {
        FolderPath *next = paths->next;
        free(paths->name);
        free(paths->path);
        free(paths);
        paths = next;
    }
}

static const FolderPath *find_folder_path(const FolderPath *paths, uint32_t folder_id) {
    for (const FolderPath *path = paths; path != NULL; path = path->next) {
        if (path->folder_id == folder_id) {
            return path;
        }
    }
    return NULL;
}

static int add_folder_path(FolderPath **paths, const LIBMTP_folder_t *folder, const char *parent_path) {
    FolderPath *path = calloc(1, sizeof(FolderPath));
    if (path == NULL) {
        return -1;
    }

    path->folder_id = folder->folder_id;
    path->parent_id = folder->parent_id;
    path->storage_id = folder->storage_id;
    path->name = copy_string(folder->name);
    path->path = join_path(parent_path, folder->name);
    if (path->path == NULL) {
        free_folder_paths(path);
        return -1;
    }

    path->next = *paths;
    *paths = path;
    return 0;
}

static int collect_folder_paths(FolderPath **paths, const LIBMTP_folder_t *folder, const char *parent_path) {
    for (const LIBMTP_folder_t *current = folder; current != NULL; current = current->sibling) {
        if (add_folder_path(paths, current, parent_path) != 0) {
            return -1;
        }

        const FolderPath *current_path = find_folder_path(*paths, current->folder_id);
        const char *child_parent_path = current_path == NULL ? parent_path : current_path->path;
        if (current->child != NULL && collect_folder_paths(paths, current->child, child_parent_path) != 0) {
            return -1;
        }
    }

    return 0;
}

static void print_device_errors(LIBMTP_mtpdevice_t *device) {
    if (device != NULL && device->errorstack != NULL) {
        LIBMTP_Dump_Errorstack(device);
        LIBMTP_Clear_Errorstack(device);
    }
}

static void print_owned_string(const char *label, char *value) {
    printf("%s: %s\n", label, value == NULL ? "unavailable" : value);
    free(value);
}

static int summarize_file(const char *path, uint64_t *bytes, uint64_t *separator_count, uint64_t *metadata_line_count) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "Could not open downloaded file for summary: %s\n", strerror(errno));
        return -1;
    }

    uint64_t byte_total = 0;
    uint64_t separators = 0;
    uint64_t metadata_lines = 0;
    char line[8192];

    while (fgets(line, sizeof(line), file) != NULL) {
        size_t length = strlen(line);
        byte_total += (uint64_t)length;

        size_t trimmed = length;
        while (trimmed > 0 && (line[trimmed - 1] == '\n' || line[trimmed - 1] == '\r' || isspace((unsigned char)line[trimmed - 1]))) {
            trimmed--;
        }

        if (trimmed == 10 && strncmp(line, "==========", 10) == 0) {
            separators++;
        }

        if (strncmp(line, "- Your Highlight", 16) == 0 ||
            strncmp(line, "- Your Note", 11) == 0 ||
            strncmp(line, "- Your Bookmark", 15) == 0) {
            metadata_lines++;
        }
    }

    if (ferror(file)) {
        fprintf(stderr, "Could not read downloaded file for summary\n");
        fclose(file);
        return -1;
    }

    fclose(file);
    *bytes = byte_total;
    *separator_count = separators;
    *metadata_line_count = metadata_lines;
    return 0;
}

static const LIBMTP_file_t *find_clippings_file(const LIBMTP_file_t *files, const FolderPath *paths) {
    const LIBMTP_file_t *fallback = NULL;

    for (const LIBMTP_file_t *file = files; file != NULL; file = file->next) {
        if (!equals_ci(file->filename, "My Clippings.txt")) {
            continue;
        }

        const FolderPath *parent = find_folder_path(paths, file->parent_id);
        printf("candidate_file: id=%u parent=%u storage=%u size=%" PRIu64 " path=%s/%s\n",
               file->item_id,
               file->parent_id,
               file->storage_id,
               file->filesize,
               parent == NULL ? "<unknown-folder>" : parent->path,
               file->filename == NULL ? "<unnamed>" : file->filename);

        if (parent != NULL && has_ci_path_component(parent->path, "documents")) {
            return file;
        }

        if (paths == NULL && fallback == NULL) {
            fallback = file;
        }
    }

    return fallback;
}

static int probe_device(LIBMTP_raw_device_t *raw_device, int device_index, const char *download_path) {
    printf("opening_device_index: %d\n", device_index);
    printf("raw_vendor: %s\n", raw_device->device_entry.vendor == NULL ? "unknown" : raw_device->device_entry.vendor);
    printf("raw_product: %s\n", raw_device->device_entry.product == NULL ? "unknown" : raw_device->device_entry.product);
    printf("raw_vendor_id: 0x%04x\n", raw_device->device_entry.vendor_id);
    printf("raw_product_id: 0x%04x\n", raw_device->device_entry.product_id);

    LIBMTP_mtpdevice_t *device = LIBMTP_Open_Raw_Device_Uncached(raw_device);
    if (device == NULL) {
        fprintf(stderr, "Could not open raw MTP device\n");
        return 10;
    }

    print_owned_string("manufacturer", LIBMTP_Get_Manufacturername(device));
    print_owned_string("model", LIBMTP_Get_Modelname(device));
    print_owned_string("serial", LIBMTP_Get_Serialnumber(device));
    print_owned_string("friendly_name", LIBMTP_Get_Friendlyname(device));

    if (LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) == 0) {
        for (LIBMTP_devicestorage_t *storage = device->storage; storage != NULL; storage = storage->next) {
            printf("storage: id=%u description=%s volume=%s max=%" PRIu64 " free=%" PRIu64 "\n",
                   storage->id,
                   storage->StorageDescription == NULL ? "unknown" : storage->StorageDescription,
                   storage->VolumeIdentifier == NULL ? "unknown" : storage->VolumeIdentifier,
                   storage->MaxCapacity,
                   storage->FreeSpaceInBytes);
        }
    } else {
        fprintf(stderr, "Could not read device storage metadata\n");
        print_device_errors(device);
    }

    printf("enumerating_folders: start\n");
    LIBMTP_folder_t *folders = LIBMTP_Get_Folder_List(device);
    FolderPath *paths = NULL;
    if (folders == NULL) {
        fprintf(stderr, "Could not read folder list\n");
        print_device_errors(device);
    } else if (collect_folder_paths(&paths, folders, "/") != 0) {
        fprintf(stderr, "Could not build folder path map\n");
        if (folders != NULL) {
            LIBMTP_destroy_folder_t(folders);
        }
        LIBMTP_Release_Device(device);
        free_folder_paths(paths);
        return 11;
    }

    for (const FolderPath *path = paths; path != NULL; path = path->next) {
        printf("folder: id=%u parent=%u storage=%u path=%s\n",
               path->folder_id,
               path->parent_id,
               path->storage_id,
               path->path == NULL ? "<unknown>" : path->path);
    }

    printf("enumerating_files: start\n");
    LIBMTP_file_t *files = LIBMTP_Get_Filelisting_With_Callback(device, NULL, NULL);
    if (files == NULL) {
        fprintf(stderr, "Could not read file list\n");
        print_device_errors(device);
        if (folders != NULL) {
            LIBMTP_destroy_folder_t(folders);
        }
        LIBMTP_Release_Device(device);
        free_folder_paths(paths);
        return 12;
    }

    const LIBMTP_file_t *clippings = find_clippings_file(files, paths);
    if (clippings == NULL) {
        fprintf(stderr, "My Clippings.txt was not found on this MTP device\n");
        LIBMTP_destroy_file_t(files);
        if (folders != NULL) {
            LIBMTP_destroy_folder_t(folders);
        }
        LIBMTP_Release_Device(device);
        free_folder_paths(paths);
        return 13;
    }

    const FolderPath *parent = find_folder_path(paths, clippings->parent_id);
    printf("selected_file_id: %u\n", clippings->item_id);
    printf("selected_file_parent: %u\n", clippings->parent_id);
    printf("selected_file_storage: %u\n", clippings->storage_id);
    printf("selected_file_reported_bytes: %" PRIu64 "\n", clippings->filesize);
    printf("selected_file_path: %s/%s\n",
           parent == NULL ? "<unknown-folder>" : parent->path,
           clippings->filename == NULL ? "<unnamed>" : clippings->filename);

    printf("download: start\n");
    int download_result = LIBMTP_Get_File_To_File(device, clippings->item_id, download_path, NULL, NULL);
    if (download_result != 0) {
        fprintf(stderr, "Could not download selected file\n");
        print_device_errors(device);
        LIBMTP_destroy_file_t(files);
        if (folders != NULL) {
            LIBMTP_destroy_folder_t(folders);
        }
        LIBMTP_Release_Device(device);
        free_folder_paths(paths);
        return 14;
    }

    uint64_t bytes = 0;
    uint64_t separators = 0;
    uint64_t metadata_lines = 0;
    if (summarize_file(download_path, &bytes, &separators, &metadata_lines) != 0) {
        LIBMTP_destroy_file_t(files);
        if (folders != NULL) {
            LIBMTP_destroy_folder_t(folders);
        }
        LIBMTP_Release_Device(device);
        free_folder_paths(paths);
        return 15;
    }

    printf("downloaded_bytes: %" PRIu64 "\n", bytes);
    printf("separator_count: %" PRIu64 "\n", separators);
    printf("metadata_line_count: %" PRIu64 "\n", metadata_lines);
    if (bytes == 0) {
        fprintf(stderr, "Downloaded My Clippings.txt is empty\n");
        LIBMTP_destroy_file_t(files);
        if (folders != NULL) {
            LIBMTP_destroy_folder_t(folders);
        }
        LIBMTP_Release_Device(device);
        free_folder_paths(paths);
        return 16;
    }

    printf("result: success\n");

    LIBMTP_destroy_file_t(files);
    if (folders != NULL) {
        LIBMTP_destroy_folder_t(folders);
    }
    LIBMTP_Release_Device(device);
    free_folder_paths(paths);
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <download-path>\n", argv[0]);
        return 64;
    }

    LIBMTP_Init();

    LIBMTP_raw_device_t *raw_devices = NULL;
    int raw_device_count = 0;
    LIBMTP_error_number_t detect_result = LIBMTP_Detect_Raw_Devices(&raw_devices, &raw_device_count);
    if (detect_result == LIBMTP_ERROR_NO_DEVICE_ATTACHED) {
        fprintf(stderr, "No MTP devices attached\n");
        return 2;
    }
    if (detect_result != LIBMTP_ERROR_NONE) {
        fprintf(stderr, "Could not enumerate raw MTP devices: %d\n", detect_result);
        return 3;
    }

    printf("raw_device_count: %d\n", raw_device_count);
    int first_failure = 4;
    for (int i = 0; i < raw_device_count; i++) {
        int result = probe_device(&raw_devices[i], i, argv[1]);
        if (result == 0) {
            free(raw_devices);
            return 0;
        }
        if (first_failure == 4) {
            first_failure = result;
        }
        printf("device_index_%d_result: %d\n", i, result);
    }

    free(raw_devices);
    return first_failure;
}
