// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
)

// config holds runtime configuration sourced from the environment, with
// production-safe defaults. Centralizing it keeps the service tunable per
// environment without code changes and gives tests a single knob to set.
type config struct {
	port                 string
	logLevel             logrus.Level
	maxAuthorLen         int
	maxCommentLen        int
	maxReviewsPerProduct int
	maxRecvMsgBytes      int
	shutdownGrace        time.Duration
}

// defaultConfig returns the config used by tests and as the baseline for env
// overrides. Limits are deliberately conservative to bound memory and abuse.
func defaultConfig() config {
	return config{
		port:                 defaultPort,
		logLevel:             logrus.InfoLevel,
		maxAuthorLen:         80,
		maxCommentLen:        1000,
		maxReviewsPerProduct: 500,
		maxRecvMsgBytes:      1 << 20, // 1 MiB
		shutdownGrace:        20 * time.Second,
	}
}

func loadConfig() config {
	c := defaultConfig()
	c.port = getEnv("PORT", c.port)
	c.logLevel = parseLevel(getEnv("LOG_LEVEL", c.logLevel.String()))
	c.maxAuthorLen = getEnvInt("MAX_AUTHOR_LEN", c.maxAuthorLen)
	c.maxCommentLen = getEnvInt("MAX_COMMENT_LEN", c.maxCommentLen)
	c.maxReviewsPerProduct = getEnvInt("MAX_REVIEWS_PER_PRODUCT", c.maxReviewsPerProduct)
	c.maxRecvMsgBytes = getEnvInt("MAX_RECV_MSG_BYTES", c.maxRecvMsgBytes)
	c.shutdownGrace = time.Duration(getEnvInt("SHUTDOWN_GRACE_SECONDS", int(c.shutdownGrace.Seconds()))) * time.Second
	return c
}

func getEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && strings.TrimSpace(v) != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v, ok := os.LookupEnv(key); ok {
		if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil {
			return n
		}
	}
	return fallback
}

func parseLevel(s string) logrus.Level {
	if lvl, err := logrus.ParseLevel(strings.TrimSpace(s)); err == nil {
		return lvl
	}
	return logrus.InfoLevel
}
