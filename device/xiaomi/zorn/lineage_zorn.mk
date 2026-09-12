#
# Copyright (C) 2024 The Android Open Source Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit from zorn device.
$(call inherit-product, device/xiaomi/zorn/device.mk)

## Device identifier
PRODUCT_DEVICE := zorn
PRODUCT_NAME := lineage_zorn
PRODUCT_BRAND := POCO
PRODUCT_MODEL := 24117RK2CG
PRODUCT_MANUFACTURER := xiaomi

# Sakura flags
SAKURA_OFFICIAL := true
SAKURA_MAINTAINER := ArmSM
SAKURA_BUILD_TYPE := gapps

# bootanimation
TARGET_BOOT_ANIMATION_RES := 1440

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc=$(call normalize-path-list, "zorn zorn 15 AQ3A.240829.003 OS2.0.202.0.VOKMIXM release-keys")

BUILD_FINGERPRINT := Xiaomi/zorn/zorn:15/AQ3A.240829.003/OS2.0.202.0.VOKMIXM:user/release-keys

# GMS
PRODUCT_GMS_CLIENTID_BASE := android-xiaomi
