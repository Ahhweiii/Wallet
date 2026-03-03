# FrugalPilot StoreKit Template

Use this file as a copy checklist when creating `FrugalPilot.storekit` in Xcode.

## 1) Create the config file

1. Xcode -> `File` -> `New` -> `StoreKit Configuration File`.
2. Name it: `FrugalPilot.storekit`.
3. Save under: `StoreKit/`.

## 2) Add one subscription group

- Group name: `FrugalPilot Pro`
- Internal group ID (any stable string): `frugalpilot.pro.group`

## 3) Add products

### Auto-Renewable Subscriptions (in `FrugalPilot Pro` group)

1. Reference Name: `Pro Lite Monthly`
   Product ID: `ahhweii.frugalpilot.prolite.monthly`
   Duration: `1 Month`

2. Reference Name: `Pro Lite Yearly`
   Product ID: `ahhweii.frugalpilot.prolite.yearly`
   Duration: `1 Year`

3. Reference Name: `Pro Monthly`
   Product ID: `ahhweii.frugalpilot.pro.monthly`
   Duration: `1 Month`

4. Reference Name: `Pro Yearly`
   Product ID: `ahhweii.frugalpilot.pro.yearly`
   Duration: `1 Year`

### Non-Consumable

5. Reference Name: `Lifetime`
   Product ID: `ahhweii.frugalpilot.lifetime`
   Type: `Non-Consumable`

## 4) Recommended local test pricing (optional)

- Pro Lite Monthly: `2.99`
- Pro Lite Yearly: `24.99`
- Pro Monthly: `4.99`
- Pro Yearly: `39.99`
- Lifetime: `99.99`

## 5) Attach config to your run scheme

1. `Product` -> `Scheme` -> `Edit Scheme...`
2. `Run` -> `Options`
3. `StoreKit Configuration` -> select `FrugalPilot.storekit`.

## 6) Quick validation checklist

- All 5 IDs exactly match what app code expects.
- 4 subscription products are in the same subscription group.
- Lifetime is non-consumable (not subscription).
- App Settings -> Subscription no longer shows "Not available" for these IDs.

