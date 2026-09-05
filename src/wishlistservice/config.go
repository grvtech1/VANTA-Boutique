// Copyright 2026 VANTA Boutique contributors
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

// config is sourced from the environment with production-safe defaults, so the
// same image is tunable per environment without a rebuild.
type config struct {
	port            string
	logLevel        logrus.Level
	maxItemsPerUser int
	maxUsers        int
	maxIDLen        int
	maxRecvMsgBytes int
	shutdownGrace   time.Duration
}

func defaultConfig() config {
	return config{
		port:            defaultPort,
		logLevel:        logrus.InfoLevel,
		maxItemsPerUser: 200,
		maxUsers:        20000,
		maxIDLen:        64,
		maxRecvMsgBytes: 256 << 10, // 256 KiB — requests carry two short IDs
		shutdownGrace:   20 * time.Second,
	}
}

func loadConfig() config {
	c := defaultConfig()
	c.port = getEnv("PORT", c.port)
	c.logLevel = parseLevel(getEnv("LOG_LEVEL", c.logLevel.String()))
	c.maxItemsPerUser = getEnvInt("MAX_ITEMS_PER_USER", c.maxItemsPerUser)
	c.maxUsers = getEnvInt("MAX_USERS", c.maxUsers)
	c.maxIDLen = getEnvInt("MAX_ID_LEN", c.maxIDLen)
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
