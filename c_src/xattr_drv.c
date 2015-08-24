#include <string.h>
#include <sys/types.h>
#include <sys/xattr.h>
#include <stdio.h>
#include <errno.h>
#include "erl_driver.h"

//#define VERBOSE

int setxattr(const char *path, const char *name,
              const void *value, size_t size, int flags);
int lsetxattr(const char *path, const char *name,
              const void *value, size_t size, int flags);
int fsetxattr(int fd, const char *name,
              const void *value, size_t size, int flags);

typedef struct {
    ErlDrvPort port;
} xattr_data;

#ifdef VERBOSE
#define DEBUG(...)    fprintf(stderr,__VA_ARGS__)
#else
#define DEBUG(...)
#endif

static int xattr_drv_init(void) {
    DEBUG("driver init ...\r\n");
    return 0;
}

static ErlDrvData xattr_drv_start(ErlDrvPort port, char* buffer) {
    DEBUG("driver started ...\r\n");
    xattr_data* d = (xattr_data*)driver_alloc(sizeof(xattr_data));
    d->port = port;
    return (ErlDrvData)d;
}

static void xattr_drv_stop(ErlDrvData handle) {
    DEBUG("driver stopped.\r\n");
    driver_free((char*)handle);
}

#define SET 1
#define GET 2
#define REMOVE 3
#define LIST 4

static void xattr_drv_output(ErlDrvData handle, char* buff, ErlDrvSizeT bufflen) {
    DEBUG("requesting output ...\r\n");
    xattr_data* d = (xattr_data*)handle;
    char fn = buff[0];
    char* path;
    char* name;
    char* value="    ";
    int size;
    int rc;
    char data;
    switch (fn) {
        case SET:
            path = buff+1;
            name = path+strlen(path)+1;
            value = name+strlen(name)+1;
            size = bufflen-strlen(path)-strlen(name)-3;
            DEBUG("- setxattr(\"%s\",\"%s\",value,%i) - ",path,name,size);
            rc = setxattr(path,name,value,size,0);
            if (rc) {
                data = (char)errno;
                DEBUG("%i\r\n",data);
                driver_output(d->port, &data, 1);
            } else {
                DEBUG("ok\r\n");
                data = 0;
                driver_output(d->port, &data, 1);
            }
            break;
        case GET:
            path = buff+1;
            name = path+strlen(path)+1;
            DEBUG("- getxattr(\"%s\",\"%s\") - ",path,name);
            size = getxattr(path,name,value,0);
            DEBUG("{%i} ",size);
            value = malloc(size+100); // get some space
            rc = getxattr(path,name,value+2,size+100-2); // reserve two bytes for the return code
            if (rc==-1) {
                data = (char)errno;
                DEBUG("%i\r\n",data);
                driver_output(d->port, &data, 1);
            } else {
                value[0] = 0;
                value[1] = GET;
                DEBUG("ok (%s)\r\n",value+2);
                driver_output(d->port, value, rc+2);
            }
            free(value);
            break;
        case REMOVE:
            path = buff+1;
            name = path+strlen(path)+1;
            DEBUG("- removexattr(\"%s\",\"%s\") - ",path,name);
            rc = removexattr(path,name);
            if (rc==-1) {
                data = (char)errno;
                DEBUG("%i\r\n",data);
                driver_output(d->port, &data, 1);
            } else {
                DEBUG("ok\r\n");
                data = 0;
                driver_output(d->port, &data, 1);
            }
            break;
        case LIST:
            path = buff+1;
            DEBUG("- listxattr(\"%s\",\"%s\") - ",path,name);
            size = listxattr(path,value,0);
            //DEBUG("{%i} ",size);
            value = malloc(size+100);
            rc = listxattr(path,value+2,size+100-2);
            if (rc==-1) {
                data = (char)errno;
                DEBUG("%i\r\n",data);
                driver_output(d->port, &data, 1);
            } else {
                value[0] = 0;
                value[1] = LIST;
                DEBUG("ok (%s)\r\n",value+2);
                driver_output(d->port, value, rc+2);
            }
            free(value);
            break;
        default:
            data = 27; //ENOTSUP;
            driver_output(d->port, (char*)&data, sizeof(data));
    }
}

static ErlDrvEntry driver_entry;

DRIVER_INIT(xattr_driver)
{
    driver_entry.init            = xattr_drv_init;
    driver_entry.start           = xattr_drv_start;
    driver_entry.stop            = xattr_drv_stop;
    driver_entry.output          = xattr_drv_output;
    driver_entry.ready_input     = NULL;
    driver_entry.ready_output    = NULL;
    driver_entry.driver_name     = "xattr_drv";
    driver_entry.finish          = NULL;
    driver_entry.handle          = NULL;
    driver_entry.control         = NULL;
    driver_entry.timeout         = NULL;
    driver_entry.outputv         = NULL;
    driver_entry.ready_async     = NULL;
    driver_entry.flush           = NULL;
    driver_entry.call            = NULL;
    driver_entry.event           = NULL;
    driver_entry.extended_marker = ERL_DRV_EXTENDED_MARKER;
    driver_entry.major_version   = ERL_DRV_EXTENDED_MAJOR_VERSION;
    driver_entry.minor_version   = ERL_DRV_EXTENDED_MINOR_VERSION;
    driver_entry.driver_flags    = 0;
    driver_entry.handle2         = NULL;
    driver_entry.process_exit    = NULL;
    driver_entry.stop_select     = NULL;
    return (ErlDrvEntry*) &driver_entry;
}
