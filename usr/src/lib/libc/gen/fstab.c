#ifndef lint
static char sccsid[] = "@(#)fstab.c	4.2 (Berkeley) %G%";
#endif

#include <fstab.h>
#include <stdio.h>
#include <ctype.h>

static	struct fstab fs;
static	char line[BUFSIZ+1];
static	FILE *fs_file = 0;

static char *
fsskip(p)
	register char *p;
{

	while (*p && *p != ':')
		++p;
	if (*p)
		*p++ = 0;
	return (p);
}

static char *
fsdigit(backp, string, end)
	int *backp;
	char *string, end;
{
	register int value = 0;
	register char *cp;

	for (cp = string; *cp && isdigit(*cp); cp++) {
		value *= 10;
		value += *cp - '0';
	}
	if (*cp == '\0')
		return (0);
	*backp = value;
	while (*cp && *cp != end)
		cp++;
	if (*cp == '\0')
		return (0);
	return (cp+1);
}

static
fstabscan(fs)
	struct fstab *fs;
{
	register char *cp;

	cp = fgets(line, 256, fs_file);
	if (cp == NULL)
		return (EOF);
	fs->fs_spec = cp;
	cp = fsskip(cp);
	fs->fs_file = cp;
	cp = fsskip(cp);
	fs->fs_type = cp;
	cp = fsskip(cp);
	fs->fs_quotafile = cp;
	cp = fsskip(cp);
	cp = fsdigit(&fs->fs_freq, cp, ':');
	if (cp == 0)
		return (4);
	cp = fsdigit(&fs->fs_passno, cp, '\n');
	if (cp == 0)
		return (5);
	return (6);
}
	
setfsent()
{

	if (fs_file)
		endfsent();
	if ((fs_file = fopen(FSTAB, "r")) == NULL){
		fs_file = 0;
		return (0);
	}
	return (1);
}

endfsent()
{

	if (fs_file)
		fclose(fs_file);
	return (1);
}

struct fstab *
getfsent()
{
	int nfields;

	if ((fs_file == 0) && (setfsent() == 0))
		return (0);
	nfields = fstabscan(&fs);
	if (nfields == EOF || nfields != 6)
		return (0);
	return (&fs);
}

struct fstab *
getfsspec(name)
	char *name;
{
	register struct fstab *fsp;

	if (setfsent() == 0)	/* start from the beginning */
		return (0);
	while((fsp = getfsent()) != 0)
		if (strcmp(fsp->fs_spec, name) == 0)
			return (fsp);
	return (0);
}

struct fstab *
getfsfile(name)
	char *name;
{
	register struct fstab *fsp;

	if (setfsent() == 0)	/* start from the beginning */
		return (0);
	while ((fsp = getfsent()) != 0)
		if (strcmp(fsp->fs_file, name) == 0)
			return (fsp);
	return (0);
}
