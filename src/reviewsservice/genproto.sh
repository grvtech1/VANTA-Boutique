#!/bin/bash -eu
#
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

# Regenerates the Go gRPC stubs for reviewsservice from ../../protos/demo.proto.
# Requires protoc + protoc-gen-go + protoc-gen-go-grpc on PATH.

PATH=$PATH:$(go env GOPATH)/bin
protodir=../../protos
outdir=./genproto

protoc --proto_path=$protodir --go_out=./$outdir --go_opt=paths=source_relative --go-grpc_out=./$outdir --go-grpc_opt=paths=source_relative $protodir/demo.proto
