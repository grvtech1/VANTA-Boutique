# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG BUILDPLATFORM=linux/amd64

FROM --platform=$BUILDPLATFORM golang:1.26.2-alpine AS builder
ARG TARGETOS=linux
ARG TARGETARCH=amd64
WORKDIR /src

# Restore dependencies (cached layer when go.mod/go.sum are unchanged).
COPY go.mod go.sum ./
RUN go mod download
COPY . .

ARG SKAFFOLD_GO_GCFLAGS
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 go build -ldflags="-s -w" -gcflags="${SKAFFOLD_GO_GCFLAGS}" -o /go/bin/reviewsservice .

FROM gcr.io/distroless/static:nonroot

WORKDIR /src
COPY --from=builder /go/bin/reviewsservice /src/reviewsservice
# The server reads PORT (see config.go); keep this in sync with the manifest.
ENV PORT=50051

ENV GOTRACEBACK=single

EXPOSE 50051
ENTRYPOINT ["/src/reviewsservice"]
