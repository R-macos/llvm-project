/* simple driver-driver which dispatches based on the -arch <arch>
   argument to the corresponding <arch>-<build>-flang driver.

   NOTE: multiple -arch flags with different architectures are not
   supported (yet) since they require multiple runs and a lipo.

   Author: Simon Urbanek <simon.urbanek@R-project.org>
   License: MIT
*/
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#ifndef BUILD
#error "BUILD must be defined"
#endif

#ifndef EXENAME
#define EXENAME "flang"
#endif

#ifdef __arm64__
#define myarch "arm64"
#endif
#ifdef __x86_64__
#define myarch "x86_64"
#endif
#ifndef myarch
#error "Unsupported architecture"
#endif

static char fn[512];

#ifdef PREFIX
/* prepend PREFIX so the prefix tools are found first */
static int add_PATH(const char *prefix) {
    char *path = getenv("PATH");
    size_t len = strlen(path) + strlen(PREFIX) + 8;
    char *npath = (char*) malloc(len);
    int n;
    if (!npath) {
	fprintf(stderr, "Out of memory.\n");
	return 1;
    }
    n = snprintf(npath, len, "%s/bin:%s", PREFIX, path);
    if (n > 0 && n < len)
	setenv("PATH", npath, 1);
    free(npath);
    return 0;
}

static int file_exists(const char *fn) {
    FILE *f = fopen(fn, "r");
    if (f) fclose(f);
    return f ? 1 : 0;
}
#endif

int main(int argc, char **argv) {
    int i = 1, j = 1, archs = 0;
    const char *arch = 0, *sdk;
    char **nargv = (char**) malloc(sizeof(char*) * (argc + 3));
    if (!nargv) return 1;
    int opts = 1;
    while (i < argc) {
	if (!strcmp(argv[i], "-arch")) {
	    if (i + 1 < argc) {
		char *newarch = argv[++i];
		/* ignore duplicates */
		if (!arch || strcmp(arch, newarch)) {
		    arch = newarch;
		    archs++;
		}
	    } else {
		fprintf(stderr, "ERROR: <arch> missing in -arch");
		return 1;
	    }
	    i++; /* we skip -arch flags as flang doesn't understand them */
	    continue;
	} else if (!strncmp(argv[i], "-mmacos-version-", 16)) {
	    /* Apple has renamed -mmacosx-version-.. options to -mmacos-version-.. but
	       gfortran doesn't know that so we map them all to the original */
	    /* (flang may not need this?) */
	    char *x = (char*) malloc(strlen(argv[i] + 2));
	    if (!x) { fprintf(stderr, "ERROR: out of memory!\n"); return 1; }
	    strcpy(x, "-mmacosx-version-");
	    strcpy(x + 17, argv[i] + 16);
	    argv[i] = x;
	} else if (!strcmp(argv[i], "-fintrinsic-modules-path"))
	    opts = 0; /* if it is there, we don't override it */
	/* we insert -fintrinsic-modules-path after frist non-option */
	/* Note that if there is no non-option then there is nothing to compile so we don't care */
	if (opts && argv[i][0] != '-') {
	    if (!arch) /* we shold be done with -arch by now */
		arch = myarch;
	    nargv[j++] = "-fintrinsic-modules-path";
	    snprintf(fn, sizeof(fn), "%s/lib/clang/23/finclude/flang/%s-%s",
		     PREFIX, arch, BUILD);
	    nargv[j++] = strdup(fn);
	    /* we need arm64 above, but tools use aarch64 */
	    if (!strcmp(arch, "arm64"))
		arch = "aarch64";
	    opts = 0;
	}
	nargv[j] = argv[i];
	j++;
	i++;
    }
    argc = j;
    if (archs > 1) {
	fprintf(stderr, "ERROR: Sorry, cannot handle multiple architectures at once, use multiple calls and lipo\n");
	return 1;
    }
    if (!arch)
	arch = myarch;
    if (!strcmp(arch, "arm64"))
	arch = "aarch64";
#ifdef PREFIX
    sdk = getenv("SDKROOT");
    if (sdk && !*sdk) sdk = 0;
    if (!sdk) { /* if there is no SDKROOT, check if the SDK link is correct */
	int ok_sdk = 1;
	snprintf(fn, sizeof(fn), "%s/SDK/SDKSettings.plist", PREFIX);
	if (!file_exists(fn)) {
	    snprintf(fn, sizeof(fn), "%s/SDK/SDKSettings.json", PREFIX);
	    if (!file_exists(fn)) { /* invalid, detect SDK */
		ok_sdk = 0;
		FILE *f = popen("/usr/bin/xcrun --show-sdk-path", "r");
		if (!f || !fgets(fn, sizeof(fn), f)) {
		    fprintf(stderr, "** ERROR: %s/SDK is invalid and cannot determine SDK path!\n\n", PREFIX);
		    if (f) fclose(f);
		    return 1;
		} else {
		    char *c = strchr(fn, '\n');
		    fclose(f);
		    if (c) *c = 0;
		    if (*fn) {
			fprintf(stderr,"Warning: %s/SDK is invalid, setting SDKROOT=%s\n  Consider running the following to fix (or set SDKROOT):\n  ln -sfn %s %s/SDK\n", PREFIX, fn, fn, PREFIX);
			setenv("SDKROOT", fn, 1);
		    }
		}
	    }
	}
	if (ok_sdk) { /* valid, set SDKROOT */
	    snprintf(fn, sizeof(fn), "%s/SDK", PREFIX);
	    setenv("SDKROOT", fn, 1);
	}
    }
    add_PATH(PREFIX);
    snprintf(fn, sizeof(fn), "%s/bin/%s-%s-%s", PREFIX, arch, BUILD, EXENAME);
#else
    snprintf(fn, sizeof(fn), "%s-%s-%s", arch, BUILD, EXENAME);
#endif
    nargv[0] = fn;
    nargv[argc] = 0;
    execvp(fn, nargv);
    fprintf(stderr, "ERROR: cannot execute %s\n", fn);
    return 1;
}
