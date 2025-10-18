#import "TSUtil.h"

#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <mach-o/dyld.h>
#import <libroot.h>

#define SIGABRT 6
#define OS_REASON_SIGNAL        2
#define OS_REASON_DYLD          6
#define DYLD_EXIT_REASON_OTHER                  9

void abort_with_payload(uint32_t reason_namespace, uint64_t reason_code,
    void *payload, uint32_t payload_size,
    const char *reason_string, uint64_t reason_flags)
    __attribute__((noreturn, cold));

#define    ASSERT(e)    (__builtin_expect(!(e), 0) ?\
 ((void)fprintf(stderr, "%s:%d: failed ASSERTion `%s'\n", __FILE_NAME__, __LINE__, #e),\
 abort_with_payload(OS_REASON_DYLD,DYLD_EXIT_REASON_OTHER,NULL,0, #e, 0)) : (void)0)


extern char **environ;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1

enum {
    PERSONA_INVALID      = 0,
    PERSONA_GUEST        = 1,
    PERSONA_MANAGED      = 2,
    PERSONA_PRIV         = 3,
    PERSONA_SYSTEM       = 4,
    PERSONA_DEFAULT      = 5,
    PERSONA_SYSTEM_PROXY = 6,
    PERSONA_SYS_EXT      = 7,
    PERSONA_ENTERPRISE   = 8,

    PERSONA_TYPE_MAX     = PERSONA_ENTERPRISE,
};

#define PERSONA_INFO_V1       1
#define PERSONA_INFO_V2       2

struct kpersona_info {
    /* v1 fields */
    uint32_t persona_info_version;

    uid_t    persona_id;
    int      persona_type;
    gid_t    persona_gid; /* unused */
    uint32_t persona_ngroups; /* unused */
    gid_t    persona_groups[NGROUPS]; /* unused */
    uid_t    persona_gmuid; /* unused */
    char     persona_name[MAXLOGNAME + 1];

    /* v2 fields */
    uid_t    persona_uid;
} __attribute__((packed));

extern int kpersona_find_by_type(int persona_type, uid_t *id, size_t *idlen);
extern int kpersona_getpath(uid_t id, char path[MAXPATHLEN]);
extern int kpersona_pidinfo(pid_t id, struct kpersona_info *info);
extern int kpersona_info(uid_t id, struct kpersona_info *info);
extern int kpersona_find(const char *name, uid_t uid, uid_t *id, size_t *idlen);
extern int kpersona_alloc(struct kpersona_info *info, uid_t *id);


int available_persona_id()
{
    struct kpersona_info info={PERSONA_INFO_V1};
    ASSERT(kpersona_pidinfo(getpid(), &info) == 0);

    int current_persona_id = info.persona_id;

    for(int t=1; t<=PERSONA_TYPE_MAX; t++)
    {
        uid_t personas[128]={0};
        size_t npersonas = 128;

        if(kpersona_find_by_type(t, personas, &npersonas) <= 0)
            continue;

        for(int i=0; i<npersonas; i++)
        {
            if(personas[i] != current_persona_id)
                return personas[i];
        }
    }
    return 0;
}

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

int fd_is_valid(int fd)
{
	return fcntl(fd, F_GETFD) != -1 || errno != EBADF;
}

NSString* getNSStringFromFile(int fd)
{
	NSMutableString* ms = [NSMutableString new];
	ssize_t num_read;
	char c;
	if(!fd_is_valid(fd)) return @"";
	while((num_read = read(fd, &c, sizeof(c))))
	{
		[ms appendString:[NSString stringWithFormat:@"%c", c]];
		if(c == '\n') break;
	}
	return ms.copy;
}

void printMultilineNSString(NSString* stringToPrint)
{
	NSCharacterSet *separator = [NSCharacterSet newlineCharacterSet];
	NSArray* lines = [stringToPrint componentsSeparatedByCharactersInSet:separator];
	for(NSString* line in lines)
	{
		NSLog(@"%@", line);
	}
}

int spawnRoot(NSString* path, NSArray* args, NSString** stdOut, NSString** stdErr)
{
	NSMutableArray* argsM = args.mutableCopy ?: [NSMutableArray new];
	[argsM insertObject:path atIndex:0];
	
	NSUInteger argCount = [argsM count];
	char **argsC = (char **)malloc((argCount + 1) * sizeof(char*));

	for (NSUInteger i = 0; i < argCount; i++)
	{
		argsC[i] = strdup([[argsM objectAtIndex:i] UTF8String]);
	}
	argsC[argCount] = NULL;

	posix_spawnattr_t attr;
	posix_spawnattr_init(&attr);
    int persona_id = available_persona_id();
    ASSERT(persona_id != 0);
	posix_spawnattr_set_persona_np(&attr, persona_id, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
	posix_spawnattr_set_persona_uid_np(&attr, 0);
	posix_spawnattr_set_persona_gid_np(&attr, 0);

	posix_spawn_file_actions_t action;
	posix_spawn_file_actions_init(&action);

	int outErr[2];
	if(stdErr)
	{
		pipe(outErr);
		posix_spawn_file_actions_adddup2(&action, outErr[1], STDERR_FILENO);
		posix_spawn_file_actions_addclose(&action, outErr[0]);
	}

	int out[2];
	if(stdOut)
	{
		pipe(out);
		posix_spawn_file_actions_adddup2(&action, out[1], STDOUT_FILENO);
		posix_spawn_file_actions_addclose(&action, out[0]);
	}
	
	pid_t task_pid;
	int status = -200;
	int spawnError = posix_spawn(&task_pid, [path UTF8String], &action, &attr, (char* const*)argsC, NULL);
	posix_spawnattr_destroy(&attr);
	for (NSUInteger i = 0; i < argCount; i++)
	{
		free(argsC[i]);
	}
	free(argsC);
	
	if(spawnError != 0)
	{
		NSLog(@"posix_spawn error %d\n", spawnError);
		return spawnError;
	}

	__block volatile BOOL _isRunning = YES;
	NSMutableString* outString = [NSMutableString new];
	NSMutableString* errString = [NSMutableString new];
	dispatch_semaphore_t sema = 0;
	dispatch_queue_t logQueue;
	if(stdOut || stdErr)
	{
		logQueue = dispatch_queue_create("com.opa334.TrollStore.LogCollector", NULL);
		sema = dispatch_semaphore_create(0);

		int outPipe = out[0];
		int outErrPipe = outErr[0];

		__block BOOL outEnabled = (BOOL)stdOut;
		__block BOOL errEnabled = (BOOL)stdErr;
		dispatch_async(logQueue, ^
		{
			while(_isRunning)
			{
				@autoreleasepool
				{
					if(outEnabled)
					{
						[outString appendString:getNSStringFromFile(outPipe)];
					}
					if(errEnabled)
					{
						[errString appendString:getNSStringFromFile(outErrPipe)];
					}
				}
			}
			dispatch_semaphore_signal(sema);
		});
	}

	do
	{
		if (waitpid(task_pid, &status, 0) != -1) {
			NSLog(@"Child status %d", WEXITSTATUS(status));
		} else
		{
			perror("waitpid");
			_isRunning = NO;
			return -222;
		}
	} while (!WIFEXITED(status) && !WIFSIGNALED(status));

	_isRunning = NO;
	if(stdOut || stdErr)
	{
		if(stdOut)
		{
			close(out[1]);
		}
		if(stdErr)
		{
			close(outErr[1]);
		}

		// wait for logging queue to finish
		dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

		if(stdOut)
		{
			*stdOut = outString.copy;
		}
		if(stdErr)
		{
			*stdErr = errString.copy;
		}
	}

	return WEXITSTATUS(status);
}

void enumerateProcessesUsingBlock(void (^enumerator)(pid_t pid, NSString* executablePath, BOOL* stop))
{
    static int maxArgumentSize = 0;
    if (maxArgumentSize == 0) {
        size_t size = sizeof(maxArgumentSize);
        if (sysctl((int[]){ CTL_KERN, KERN_ARGMAX }, 2, &maxArgumentSize, &size, NULL, 0) == -1) {
            perror("sysctl argument size");
            maxArgumentSize = 4096; // Default
        }
    }
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    struct kinfo_proc *info;
    size_t length;
    int count;
    
    if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0)
        return;
    if (!(info = malloc(length)))
        return;
    if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
        free(info);
        return;
    }
    count = length / sizeof(struct kinfo_proc);
    for (int i = 0; i < count; i++) {
        @autoreleasepool {
        pid_t pid = info[i].kp_proc.p_pid;
        if (pid == 0) {
            continue;
        }
        size_t size = maxArgumentSize;
        char* buffer = (char *)malloc(length);
        if (sysctl((int[]){ CTL_KERN, KERN_PROCARGS2, pid }, 3, buffer, &size, NULL, 0) == 0) {
            NSString* executablePath = [NSString stringWithCString:(buffer+sizeof(int)) encoding:NSUTF8StringEncoding];
            
            BOOL stop = NO;
            enumerator(pid, executablePath, &stop);
            if(stop)
            {
                free(buffer);
                break;
            }
        }
        free(buffer);
        }
    }
    free(info);
}

void killall(NSString* processName, BOOL softly)
{
    enumerateProcessesUsingBlock(^(pid_t pid, NSString* executablePath, BOOL* stop)
    {
        if([executablePath.lastPathComponent isEqualToString:processName])
        {
            if(softly)
            {
                kill(pid, SIGTERM);
            }
            else
            {
                kill(pid, SIGKILL);
            }
        }
    });
}
