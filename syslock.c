#include <stdio.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#define PREREQS             ""
#define PKGNAME             "syslock"
#define NOLOCK_FILE         "/nolock"
#define CMDLINE_BUFSZ       256

#define ROOT_OVERLAY_MOUNT        "/mnt/overlay"
#define ROOT_OVERLAY_INNER_BASE   "/mnt/overlay/.lock"
#define ROOT_OVERLAY_OUTER_BASE   "/.lock"
#define ROOT_OVERLAY_UPPER        "/.lock/rw"
#define ROOT_OVERLAY_LOWER        "/.lock/ro"
#define ROOT_OVERLAY_WORK         "/.lock/.work"

#define DEFAULT_DIRPERMS    (S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH)

void log_msg(char const *fmt, ...)
{

}

void log_warning_msg(

int check_disabled()
{
	ssize_t usable = CMDLINE_BUFSZ;
	ssize_t used = 0;
	ssize_t nbytes;
	char *cmdbuf;
	char *newbuf;
	char *param;
	int fd;

	if (access(NOLOCK_FILE, F_OK) != -1)
		return (1);

	fd = open("/proc/cmdline", O_RDONLY);

	if (fd == -1)
		return (-1);
	
	cmdbuf = malloc(sizeof(char) * bufsz);

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
	int nolock;
	int ret;

	if (argc > 1 && !strcmp(argv[1], "prereqs") {
		printf(PREREQS);
		return (0);
	}

	if (nolock = check_disabled()) {
		if (nolock == -1)
			return (1)

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
