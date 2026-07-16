local ffi = require "ffi"
local ffi_str = ffi.string
local ffi_errno = ffi.errno
local lib = ffi.C

local IS_64_BIT = ffi.abi('64bit')

ffi.cdef([[
    char* strerror(int errnum);
    long syscall(int number, ...);
]])

local function errno()
    return ffi_str(lib.strerror(ffi_errno()))
end

-- Linux only. Reads a file's st_mtime through a raw stat/newfstatat syscall via
-- the libc syscall() wrapper. We go through syscall() rather than the stat64()
-- symbol because newer musl (Alpine 3.19+) no longer exports stat64, so calling
-- it directly fails at load time with "Symbol not found: stat64".
-- See https://github.com/justincormack/ljsyscall/tree/master/syscall
local function get_stat_func()
    assert(ffi.os == 'Linux', "red.stat: only Linux is supported")
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
        stat_syscall_num = 195
    elseif ARCH == 'arm64' then
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
        ]])
        -- arm64 has no plain stat syscall; use newfstatat(AT_FDCWD, path, buf, 0).
        -- Integer args are cast to long so they occupy full syscall registers.
        local AT_FDCWD = ffi.cast("long", -100)
        local no_flags = ffi.cast("long", 0)
        return function(filepath, buf)
            return lib.syscall(79, AT_FDCWD, filepath, buf, no_flags)
        end
    elseif ARCH == 'arm' then
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
            return lib.syscall(stat_syscall_num, filepath, buf)
        end
    end

    ffi.cdef('typedef struct {} stat_t;')
    return function() error("red.stat: unsupported Linux architecture: " .. tostring(ARCH)) end
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
