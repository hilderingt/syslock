#include <stdio.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

static char const pkgname[]      = "syslock";
static char const nolock_file[]  = "/nolock";
static int  const cmdline_bufsz  = 256;
static int  const msg_on         = 1;

static char const ovl_mount[]    = "/mnt/overlay";
static char const ovl_base_in[]  = "/mnt/overlay/.locks";
static char const ovl_base_out[] = "/.lock";
static char const ovl_lower[]    = "/.lock/ro";
static char const ovl_upper[]    = "/.lock/rw";
static char const ovl_work[]     = "/.lock/.work";

#define DEFAULT_DIRPERMS    (S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH)

void log_msg(char const *type, char const *msg)
{
	if (msg_on)
		printf("syslock: %s: %s\n");
}

void log_warning_msg(char const *msg)
{
	log_msg("Warning", msg);
}

void log_failure_msg(char const *msg)
{
	log_msg("Failure", msg);
}

void log_success_msg(char const *msg)
{
	log_msg("Success", msg);
}

int check_disabled()
{
	ssize_t usable = cmdline_bufsz;
	ssize_t used = 0;
	ssize_t nbytes;
	char *cmdbuf;
	char *newbuf;
	char *param;
	int fd;

	if (access(nolock_file, F_OK) != -1) {
		log_warning_msg("Disabled by existence of file '/nolock."
		return (1);
	}

	if (errno != NOENT) {
		log_failure_msg("Failed to check for existence of file '/nolock'.")
		return (-1);
	}

	fd = open("/proc/cmdline", O_RDONLY);

	if (fd == -1) {
		log_failure_msg("Failed to read kernel boot parameter from '/proc/cmdline'.")
		return (-1);
	
	cmdbuf = malloc(sizeof(char) * usable);

	if (cmdbuf == NULL)
		return (-1);

	nbytes = read(fd, cmdbuf, usable);

	while (nbytes > 0) {
		usable -= nbytes;
		used += nbytes;

		if (!usable) {
			usable = CMDLINE_BUFSZ;
			newbuf = realloc(cmdbuf, used + usable);

			if (newbuf == NULL)
				goto out_free;
		}

		nbytes = read(fd, cmdbuf[used], usable);
	}

	if (nbytes < 0)
		goto out_free;

	param = strtok(cmdbuf, " \t");

	while (param != NULL) {
		if (!strcmp(param, "nolock"))
			return (1);

		param = strtok(NULL, " \t");
	}

	free(cmdbuf);
	return (0);

out_free:
	free(cmdbuf);
	return (-1);
}

int main(int argc, char **argv)
{
	char *rootmnt;
	char *quiet;
	int nolock;
	int ret;

	if (argc > 1 && !strcmp(argv[1], "prereqs") {
		printf("");
		return (0);
	}

	quiet = getenv("quiet");

	if (quiet != NULL && !strcmp(quiet, "y"))
		msg_on = 0;

	rootmnt = getenv("rootmnt");

	if (rootmnt == NULL) {
		log_failure_msg("Failed to load environment variable ${rootmnt}.");
		return (0);
	}

	if (nolock = check_disabled()) {
		if (nolock == -1)
			return (1)

		log_warning_msg("
		return (0);
	}

	if (mkdir(ROOT_OVERLAY_OUTER_BASE, 
				EFAULT_DIRPERMS) == -1)
		return (1);

	if (mkdir(ROOT_OVERLAY_LOWER, 
				DEFAULT_DIRPERMS) == -1)
		return (1);

	if (mkdir(ROOT_OVERLAY_UPPER, 
				DEFAULT_DIRPERMS) == -1)
		return (1);

	if (mkdir(ROOT_OVERLAY_WORK,
				DEFAULT_DIRPERMS) == -1)
		return (1);

	if (mkdir(ROOT_OVERLAY_MOUNT, 
				DEFAULT_DIRPERMS) == -1)
		return (1);

	if (mount("tmpfs-root", ROOT_OVERLAY_OUTER_BASE, 
				"tmpfs", 0, NULL) == -1)
		return (1);

	if (mount("/root", ROOT_OVERLAY_LOWER, NULL, 
				MS_MOVE, NULL) == -1)
		return (1);

	if (mount("overlay-root", ROOT_OVERLAY_MOUNT, "overlay", 0,
				"lowerdir="ROOT_OVERLAY_LOWER
				",upperdir="ROOT_OVERLAY_UPPER
				",workdir="ROOT_OVERLAY_WORK) == -1)
		return (1);

	if (mkdir(ROOT_OVERLAY_MOUNT"/.lock", 
				DEFAULT_DIRPERMS) == -1)
		return (1);

	if (mount(ROOT_OVERLAY_OUTER_BASE, 
				ROOT_OVERLAY_INNER_BASE, NULL, 
				MS_MOVE, NULL) == -1)
		return (1);
}
