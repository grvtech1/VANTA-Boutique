package main

import (
	"os"
	"time"

	"github.com/sirupsen/logrus"
)

var deploymentDetailsMap map[string]string
var log *logrus.Logger

func init() {
	initializeLogger()
	loadDeploymentDetails()
}

func initializeLogger() {
	log = logrus.New()
	log.Level = logrus.DebugLevel
	log.Formatter = &logrus.JSONFormatter{
		FieldMap: logrus.FieldMap{
			logrus.FieldKeyTime:  "timestamp",
			logrus.FieldKeyLevel: "severity",
			logrus.FieldKeyMsg:   "message",
		},
		TimestampFormat: time.RFC3339Nano,
	}
	log.Out = os.Stdout
}

// loadDeploymentDetails records where this replica runs, for the footer/debug view.
// Cloud-neutral: values come from the pod (hostname) and the Downward API / env
// (CLUSTER_NAME, ZONE) instead of a provider metadata server.
func loadDeploymentDetails() {
	podHostname, err := os.Hostname()
	if err != nil {
		log.Error("Failed to fetch the hostname for the Pod", err)
	}

	deploymentDetailsMap = map[string]string{
		"HOSTNAME":    podHostname,
		"CLUSTERNAME": os.Getenv("CLUSTER_NAME"),
		"ZONE":        os.Getenv("ZONE"),
	}

	log.WithFields(logrus.Fields{
		"cluster":  deploymentDetailsMap["CLUSTERNAME"],
		"zone":     deploymentDetailsMap["ZONE"],
		"hostname": podHostname,
	}).Debug("Loaded deployment details")
}
