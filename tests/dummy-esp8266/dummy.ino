/*
 * Build-chain test sketch. Deliberately fails to compile when the builder
 * drops inputs it is supposed to pass through, so that silent regressions
 * become loud ones.
 */
#include "environment.h"

#ifndef THINX_SMOKE_CFLAG
#error "cflags from environment.json never reached the compiler"
#endif

#ifndef THINX_SMOKE_CFLAG2
#error "only the first cflag arrived -- argv word-splitting regression"
#endif

#ifndef ENVIRONMENT_SSID
#error "environment.h was not generated from environment.json"
#endif

void setup() {
  Serial.begin(115200);
  Serial.println(ENVIRONMENT_SSID);
}

void loop() {}
