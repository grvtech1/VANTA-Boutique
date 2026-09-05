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
	"fmt"
	"strconv"
	"strings"

	pb "github.com/grvtech1/VANTA-Boutique/src/frontend/genproto"
)

// currencyLogos maps ISO 4217 codes to the symbol shown before an amount.
var currencyLogos = map[string]string{
	"INR": "₹",
	"USD": "$",
	"CAD": "$",
	"JPY": "¥",
	"EUR": "€",
	"TRY": "₺",
	"GBP": "£",
}

// zeroDecimalCurrencies are displayed without a fractional part.
var zeroDecimalCurrencies = map[string]bool{"JPY": true}

// renderMoney formats a Money value for display: symbol, grouped whole units
// and two decimals — "₹1,29,999.00" for rupees (Indian lakh/crore grouping),
// "$1,299.99" elsewhere, "¥12,999" for yen.
func renderMoney(money pb.Money) string {
	code := money.GetCurrencyCode()
	units := money.GetUnits()
	nanos := money.GetNanos()

	sign := ""
	if units < 0 || nanos < 0 {
		sign = "-"
		if units < 0 {
			units = -units
		}
		if nanos < 0 {
			nanos = -nanos
		}
	}

	whole := groupDigits(strconv.FormatInt(units, 10), code == "INR")
	if zeroDecimalCurrencies[code] {
		return sign + renderCurrencyLogo(code) + whole
	}
	return fmt.Sprintf("%s%s%s.%02d", sign, renderCurrencyLogo(code), whole, nanos/10000000)
}

func renderCurrencyLogo(currencyCode string) string {
	if logo, ok := currencyLogos[currencyCode]; ok {
		return logo
	}
	return "$"
}

// groupDigits inserts thousands separators. Indian grouping puts a separator
// after the last three digits and then every two: 12,34,567. Western grouping
// is every three: 1,234,567.
func groupDigits(digits string, indian bool) string {
	if len(digits) <= 3 {
		return digits
	}
	var groups []string
	rest := digits
	// the rightmost group is always three digits
	groups = append(groups, rest[len(rest)-3:])
	rest = rest[:len(rest)-3]

	size := 3
	if indian {
		size = 2
	}
	for len(rest) > size {
		groups = append(groups, rest[len(rest)-size:])
		rest = rest[:len(rest)-size]
	}
	if rest != "" {
		groups = append(groups, rest)
	}
	// groups were collected right-to-left
	for i, j := 0, len(groups)-1; i < j; i, j = i+1, j-1 {
		groups[i], groups[j] = groups[j], groups[i]
	}
	return strings.Join(groups, ",")
}
