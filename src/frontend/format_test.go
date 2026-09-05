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
	"testing"

	pb "github.com/grvtech1/VANTA-Boutique/src/frontend/genproto"
)

func TestGroupDigits(t *testing.T) {
	cases := []struct {
		in     string
		indian bool
		want   string
	}{
		{"0", true, "0"},
		{"999", true, "999"},
		{"1000", true, "1,000"},
		{"12345", true, "12,345"},
		{"123456", true, "1,23,456"},
		{"1234567", true, "12,34,567"},
		{"12345678", true, "1,23,45,678"},
		{"123456789", true, "12,34,56,789"},
		{"1000", false, "1,000"},
		{"1234567", false, "1,234,567"},
		{"123456789", false, "123,456,789"},
	}
	for _, tc := range cases {
		if got := groupDigits(tc.in, tc.indian); got != tc.want {
			t.Errorf("groupDigits(%q, indian=%v) = %q, want %q", tc.in, tc.indian, got, tc.want)
		}
	}
}

func TestRenderMoney(t *testing.T) {
	cases := []struct {
		name string
		m    pb.Money
		want string
	}{
		{"rupees lakh grouping", pb.Money{CurrencyCode: "INR", Units: 129999, Nanos: 0}, "₹1,29,999.00"},
		{"rupees small", pb.Money{CurrencyCode: "INR", Units: 1587, Nanos: 200000000}, "₹1,587.20"},
		{"rupees paise", pb.Money{CurrencyCode: "INR", Units: 0, Nanos: 500000000}, "₹0.50"},
		{"dollars", pb.Money{CurrencyCode: "USD", Units: 1299, Nanos: 990000000}, "$1,299.99"},
		{"euros", pb.Money{CurrencyCode: "EUR", Units: 19, Nanos: 990000000}, "€19.99"},
		{"yen no decimals", pb.Money{CurrencyCode: "JPY", Units: 12999, Nanos: 0}, "¥12,999"},
		{"negative", pb.Money{CurrencyCode: "INR", Units: -1500, Nanos: -250000000}, "-₹1,500.25"},
		{"unknown code falls back to $", pb.Money{CurrencyCode: "XXX", Units: 5, Nanos: 0}, "$5.00"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := renderMoney(tc.m); got != tc.want {
				t.Errorf("renderMoney = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestRenderCurrencyLogo(t *testing.T) {
	if got := renderCurrencyLogo("INR"); got != "₹" {
		t.Errorf("INR logo = %q", got)
	}
	if got := renderCurrencyLogo("ZZZ"); got != "$" {
		t.Errorf("unknown logo should fall back to $, got %q", got)
	}
}
