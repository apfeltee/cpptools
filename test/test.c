
/* this is a test file for cppunc - it's ****not**** supposed to make sense. */

/* SHOULD BE REMOVED */
#include \
    <stdio.h>\


static const short quantum_count;

/* SHOULD BE REMOVED */
#pragma quantum_count ( this is\
    probably \
        not \
                how \
                    this dir \
                        works but idgaf)

struct dumb {
    union this_is_not_how_you_use_unions {
        #if __crapwareltd_cpp__
            int crapware_fix_count;
        #endif
        char somemore;
    } thanks_tell_me_more;
};
const char bighuge[(int)2e935] = {255};


/* SHOULD REMAIN */
    #               warning \
your \
                                    stuff\
                                    is\
        broken

static const struct dumb hugeness;