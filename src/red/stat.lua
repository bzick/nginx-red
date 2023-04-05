local ffi = require "ffi"
local ffi_str = ffi.string
local ffi_errno = ffi.errno
local lib = ffi.C

local IS_64_BIT = ffi.abi('64bit')
local OS = ffi.os

ffi.cdef([[
    char* strerror(int errnum);
]])

local function errno()
    return ffi_str(lib.strerror(ffi_errno()))
end

-- See https://github.com/justincormack/ljsyscall/tree/master/syscall
local function get_stat_func()
    if OS == 'Linux' then
        ffi.cdef([[
        long syscall(int number, ...);
    ]])
        local ARCH = ffi.arch

        local stat_syscall_num
        if ARCH == 'x64' then
            ffi.cdef([[
                typedef struct {
                    unsigned long   st_dev;
                    unsigned long   st_ino;
                    unsigned long   st_nlink;
                    unsigned int    st_mode;
                    unsigned int    st_uid;
                    unsigned int    st_gid;
                    unsigned int    __pad0;
                    unsigned long   st_rdev;
                    long            st_size;
                    long            st_blksize;
                    long            st_blocks;
                    unsigned long   st_atime;
                    unsigned long   st_atime_nsec;
                    unsigned long   st_mtime;
                    unsigned long   st_mtime_nsec;
                    unsigned long   st_ctime;
                    unsigned long   st_ctime_nsec;
                    long            __unused[3];
                } stat_t;
            ]])
            stat_syscall_num = 4
        elseif ARCH == 'x86' then
            ffi.cdef([[
                typedef struct {
                    unsigned long long      st_dev;
                    unsigned char   __pad0[4];
                    unsigned long   __st_ino;
                    unsigned int    st_mode;
                    unsigned int    st_nlink;
                    unsigned long   st_uid;
                    unsigned long   st_gid;
                    unsigned long long      st_rdev;
                    unsigned char   __pad3[4];
                    long long       st_size;
                    unsigned long   st_blksize;
                    unsigned long long      st_blocks;
                    unsigned long   st_atime;
                    unsigned long   st_atime_nsec;
                    unsigned long   st_mtime;
                    unsigned int    st_mtime_nsec;
                    unsigned long   st_ctime;
                    unsigned long   st_ctime_nsec;
                    unsigned long long      st_ino;
                } stat_t;
            ]])
            stat_syscall_num = IS_64_BIT and 106 or 195
        elseif ARCH == 'arm64'then
            ffi.cdef([[
                typedef struct {
                    unsigned long   st_dev;
                    unsigned long   st_ino;
                    unsigned int    st_mode;
                    unsigned int    st_nlink;
                    unsigned int    st_uid;
                    unsigned int    st_gid;
                    unsigned long   st_rdev;
                    unsigned long   __pad1;
                    long            st_size;
                    int             st_blksize;
                    int             __pad2;
                    long            st_blocks;
                    long            st_atime;
                    unsigned long   st_atime_nsec;
                    long            st_mtime;
                    unsigned long   st_mtime_nsec;
                    long            st_ctime;
                    unsigned long   st_ctime_nsec;
                    unsigned int    __unused4;
                    unsigned int    __unused5;
                } stat_t;

                int stat64(const char *path, stat_t *buf);
            ]])
            return lib.stat64
        elseif ARCH == 'arm' then
            if IS_64_BIT then
                ffi.cdef([[
                    typedef struct {
                        unsigned long   st_dev;
                        unsigned long   st_ino;
                        unsigned int    st_mode;
                        unsigned int    st_nlink;
                        unsigned int    st_uid;
                        unsigned int    st_gid;
                        unsigned long   st_rdev;
                        unsigned long   __pad1;
                        long            st_size;
                        int             st_blksize;
                        int             __pad2;
                        long            st_blocks;
                        long            st_atime;
                        unsigned long   st_atime_nsec;
                        long            st_mtime;
                        unsigned long   st_mtime_nsec;
                        long            st_ctime;
                        unsigned long   st_ctime_nsec;
                        unsigned int    __unused4;
                        unsigned int    __unused5;
                    } stat;
                ]])
                stat_syscall_num = 106
            else
                ffi.cdef([[
                    typedef struct {
                        unsigned long long      st_dev;
                        unsigned char   __pad0[4];
                        unsigned long   __st_ino;
                        unsigned int    st_mode;
                        unsigned int    st_nlink;
                        unsigned long   st_uid;
                        unsigned long   st_gid;
                        unsigned long long      st_rdev;
                        unsigned char   __pad3[4];
                        long long       st_size;
                        unsigned long   st_blksize;
                        unsigned long long      st_blocks;
                        unsigned long   st_atime;
                        unsigned long   st_atime_nsec;
                        unsigned long   st_mtime;
                        unsigned int    st_mtime_nsec;
                        unsigned long   st_ctime;
                        unsigned long   st_ctime_nsec;
                        unsigned long long      st_ino;
                    } stat_t;
                ]])
                stat_syscall_num = 195
            end
        elseif ARCH == 'ppc' or ARCH == 'ppcspe' then
            ffi.cdef([[
                typedef struct {
                    unsigned long long st_dev;
                    unsigned long long st_ino;
                    unsigned int    st_mode;
                    unsigned int    st_nlink;
                    unsigned int    st_uid;
                    unsigned int    st_gid;
                    unsigned long long st_rdev;
                    unsigned long long __pad1;
                    long long       st_size;
                    int             st_blksize;
                    int             __pad2;
                    long long       st_blocks;
                    int             st_atime;
                    unsigned int    st_atime_nsec;
                    int             st_mtime;
                    unsigned int    st_mtime_nsec;
                    int             st_ctime;
                    unsigned int    st_ctime_nsec;
                    unsigned int    __unused4;
                    unsigned int    __unused5;
                } stat_t;
            ]])
            stat_syscall_num = IS_64_BIT and 106 or 195
        elseif ARCH == 'mips' or ARCH == 'mipsel' then
            ffi.cdef([[
                typedef struct {
                    unsigned long   st_dev;
                    unsigned long   __st_pad0[3];
                    unsigned long long      st_ino;
                    mode_t          st_mode;
                    nlink_t         st_nlink;
                    uid_t           st_uid;
                    gid_t           st_gid;
                    unsigned long   st_rdev;
                    unsigned long   __st_pad1[3];
                    long long       st_size;
                    time_t          st_atime;
                    unsigned long   st_atime_nsec;
                    time_t          st_mtime;
                    unsigned long   st_mtime_nsec;
                    time_t          st_ctime;
                    unsigned long   st_ctime_nsec;
                    unsigned long   st_blksize;
                    unsigned long   __st_pad2;
                    long long       st_blocks;
                    long __st_padding4[14];
                } stat_t;
            ]])
            stat_syscall_num = IS_64_BIT and 4106 or 4213
        end

        if stat_syscall_num then
            return function(filepath, buf)
                return lib.syscall(stat_syscall_num, filepath, buf, ffi.sizeof("stat"))
            end
        else
            ffi.cdef('typedef struct {} stat;')
            return function() error("TODO support other Linux architectures") end
        end
    elseif OS == 'OSX' then
        ffi.cdef([[
        struct timespec {
            time_t tv_sec;
            long tv_nsec;
        };
        typedef struct {
            uint32_t        st_dev;
            uint16_t        st_mode;
            uint16_t        st_nlink;
            uint64_t        st_ino;
            uint32_t        st_uid;
            uint32_t        st_gid;
            uint32_t        st_rdev;
            struct timespec st_atimespec;
            struct timespec st_mtimespec;
            struct timespec st_ctimespec;
            struct timespec st_birthtimespec;
            int64_t         st_size;
            int64_t         st_blocks;
            int32_t         st_blksize;
            uint32_t        st_flags;
            uint32_t        st_gen;
            int32_t         st_lspare;
            int64_t         st_qspare[2];
        } stat_t;
        int stat64(const char *path, stat_t *buf);
    ]])
        return lib.stat64
    else
        ffi.cdef('typedef struct {} stat_t;')
        return function() error('TODO: support other posix system') end
    end
end
local stat_func = get_stat_func()


return function(path)
    local stat_b = ffi.new("stat_t")
    local result = stat_func(path, stat_b)
    if result == 0 then
        return tonumber(stat_b.st_mtime)
    else
        return 0, string.format("stat of '%s' failed: %s", tostring(path), errno())
    end
end