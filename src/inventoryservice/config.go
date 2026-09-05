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

// config is sourced from the environment with production-safe defaults.
type config struct {
	port              string
	logLevel          logrus.Level
	lowStockThreshold int32
	seedFile          string
	maxIDs            int
	maxRecvMsgBytes   int
	shutdownGrace     time.Duration
}

func defaultConfig() config {
	return config{
		port:              defaultPort,
		logLevel:          logrus.InfoLevel,
		lowStockThreshold: 5,
		maxIDs:            200,
		maxRecvMsgBytes:   256 << 10, // 256 KiB
		shutdownGrace:     20 * time.Second,
	}
}

func loadConfig() config {
	c := defaultConfig()
	c.port = getEnv("PORT", c.port)
	c.logLevel = parseLevel(getEnv("LOG_LEVEL", c.logLevel.String()))
	c.lowStockThreshold = int32(getEnvInt("LOW_STOCK_THRESHOLD", int(c.lowStockThreshold)))
	c.seedFile = getEnv("INVENTORY_SEED_FILE", "")
	c.maxIDs = getEnvInt("MAX_IDS_PER_REQUEST", c.maxIDs)
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
