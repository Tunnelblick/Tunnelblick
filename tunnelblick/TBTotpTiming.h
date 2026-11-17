// Timing shared by automatic TOTP authentication and its regression tests.
#ifndef TB_TOTP_TIMING_H
#define TB_TOTP_TIMING_H

#include <math.h>

enum { TBTotpPeriod = 30, TBTotpMinimumValidity = 5, TBTotpMaximumRetries = 2 };

static inline double TBTotpFreshCodeDelay(double now) {
    double remaining = TBTotpPeriod - fmod(now, TBTotpPeriod);
    return remaining <= TBTotpMinimumValidity ? remaining + 1.0 : 0.0;
}

static inline double TBTotpRetryNotBefore(double now, double lastCodeTime) {
    // Never resend the rejected time step, even if the system clock moves back.
    return fmax(now + 1.0, (floor(lastCodeTime / TBTotpPeriod) + 1.0) * TBTotpPeriod + 1.0);
}

#endif
