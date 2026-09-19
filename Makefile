.PHONY: all install deps release debug

# Xpier 发布流（陌生人 clone 回来就三步；作者日常改代码只用 dist/install）：
#   make              自动备依赖 + 编引擎（约30分钟，一辈子一次）+ 取码表 + 编App + 打包
#   make test         不装机验引擎（probe 矩阵断言，不过就失败）
#   make install      装到 ~/Library（必须本人执行；agent 沙箱写不进 ~/Library）
all: bootstrap librime wubi86-data dist

install: install-user

RIME_BIN_DIR = librime/dist/bin
RIME_LIB_DIR = librime/dist/lib
DERIVED_DATA_PATH = build

RIME_LIBRARY_FILE_NAME = librime.1.dylib
RIME_LIBRARY = lib/$(RIME_LIBRARY_FILE_NAME)

RIME_DEPS = librime/lib/libmarisa.a \
	librime/lib/libleveldb.a \
	librime/lib/libopencc.a \
	librime/lib/libyaml-cpp.a
PLUM_DATA = bin/rime-install \
	data/plum/default.yaml \
	data/plum/symbols.yaml \
	data/plum/essay.txt
OPENCC_DATA = data/opencc/TSCharacters.ocd2 \
	data/opencc/TSPhrases.ocd2 \
	data/opencc/t2s.json
SPARKLE_FRAMEWORK = Frameworks/Sparkle.framework
PACKAGE = package/Xpier.pkg
DEPS_CHECK = $(RIME_LIBRARY) $(PLUM_DATA) $(OPENCC_DATA) $(SPARKLE_FRAMEWORK)

OPENCC_DATA_OUTPUT = librime/share/opencc/*.*
PLUM_DATA_OUTPUT = plum/output/*.*
PLUM_OPENCC_OUTPUT = plum/output/opencc/*.*
RIME_PACKAGE_INSTALLER = plum/rime-install

# 五笔码表来源（构建时拷进 data/plum）。默认上游地址；发布前换成你自己的
# fork（含𡋤那几个本地提交），否则编出来的包没有𡋤（见 README 作者待办）。
# 缺目录时自动 clone，用户只管 make。
WUBI_REPO ?= https://github.com/KyleBing/rime-wubi86-jidian.git
WUBI_REF ?= master
WUBI86_DIR ?= ../rime-wubi86-jidian

# 码表兄弟目录不在就自动 clone（发布流 make 的第一步），免得用户手动对路径。
.PHONY: wubi86-checkout
wubi86-checkout:
	@if [ -f "$(WUBI86_DIR)/wubi86_jidian.schema.yaml" ]; then echo "码表目录已在：$(WUBI86_DIR)"; \
	else echo "码表目录不在，自动 clone（$(WUBI_REPO) @ $(WUBI_REF)）…"; \
	git clone --depth 1 --branch "$(WUBI_REF)" "$(WUBI_REPO)" "$(WUBI86_DIR)"; fi

INSTALL_NAME_TOOL = $(shell xcrun -find install_name_tool)
INSTALL_NAME_TOOL_ARGS = -add_rpath @loader_path/../Frameworks

.PHONY: librime copy-rime-binaries

$(RIME_LIBRARY):
	$(MAKE) librime

$(RIME_DEPS):
	$(MAKE) -C librime deps

librime: $(RIME_DEPS)
	$(MAKE) -C librime release install
	$(MAKE) copy-rime-binaries

copy-rime-binaries:
	cp -L $(RIME_LIB_DIR)/$(RIME_LIBRARY_FILE_NAME) lib/
	mkdir -p lib/rime-plugins
	cp $(RIME_BIN_DIR)/rime_deployer bin/
	cp $(RIME_BIN_DIR)/rime_dict_manager bin/
	$(INSTALL_NAME_TOOL) $(INSTALL_NAME_TOOL_ARGS) bin/rime_deployer
	$(INSTALL_NAME_TOOL) $(INSTALL_NAME_TOOL_ARGS) bin/rime_dict_manager

.PHONY: data plum-data opencc-data copy-plum-data copy-opencc-data

data: plum-data opencc-data wubi86-data

$(PLUM_DATA):
	$(MAKE) plum-data

$(OPENCC_DATA):
	$(MAKE) opencc-data

plum-data:
	@if [ -d plum/output ] && ls plum/output/*.yaml >/dev/null 2>&1 && [ -z "$(PLUM_REBUILD)" ]; then \
	  echo "plum/output 已在，跳过下载（强制重下：make PLUM_REBUILD=1）"; \
	else $(MAKE) -C plum; fi
ifdef PLUM_TAG
	rime_dir=plum/output bash plum/rime-install $(PLUM_TAG)
endif
	$(MAKE) copy-plum-data

opencc-data:
	@if [ -f data/opencc/TSCharacters.ocd2 ] && [ -f data/opencc/t2s.json ] && [ -z "$(OPENCC_REBUILD)" ]; then \
	  echo "data/opencc 已在，跳过编译（强制重编：make OPENCC_REBUILD=1）"; \
	else $(MAKE) -C librime deps/opencc; $(MAKE) copy-opencc-data; fi

copy-plum-data:
	mkdir -p data/plum
	cp $(PLUM_DATA_OUTPUT) data/plum/
	cp $(RIME_PACKAGE_INSTALLER) bin/

copy-opencc-data:
	mkdir -p data/opencc
	cp $(OPENCC_DATA_OUTPUT) data/opencc/
	cp $(PLUM_OPENCC_OUTPUT) data/opencc/ > /dev/null 2>&1 || true

# FR-1: 将极点 86 码表并入分发数据目录，并把 wubi86_jidian 设为默认首选方案
.PHONY: wubi86-data
wubi86-data: plum-data wubi86-checkout
	mkdir -p data/plum
	cp $(WUBI86_DIR)/*.schema.yaml $(WUBI86_DIR)/*.dict.yaml $(WUBI86_DIR)/LICENSE data/plum/
	cp dict/wubi86_xpier.dict.yaml data/plum/
	python3 tools/patch_default_schema.py data/plum/default.yaml wubi86_jidian
	python3 tools/patch_ascii_composer.py data/plum/default.yaml
	python3 tools/patch_wubi_local_tweaks.py data/plum/wubi86_jidian.schema.yaml
	python3 tools/patch_wubi_overlay_import.py data/plum/wubi86_jidian.dict.yaml wubi86_xpier

# Xpier：构建期强制施加的补丁，每次构建都重新确认一遍，
# 杜绝「设置里勾了但引擎没变」这类回归。脚本幂等，无变化时不改写文件。
.PHONY: xpier-patches
xpier-patches:
	python3 tools/patch_default_schema.py data/plum/default.yaml wubi86_jidian
	python3 tools/patch_drop_schemas.py data/plum/default.yaml quick5
	python3 tools/patch_ascii_composer.py data/plum/default.yaml
	python3 tools/patch_key_binder.py data/plum/default.yaml
	python3 tools/patch_save_options.py data/plum/default.yaml zh_trad quote_pair
	python3 tools/patch_wubi_wildcard.py data/plum/wubi86_jidian.schema.yaml
	python3 tools/patch_wubi_deps.py data/plum/wubi86_jidian.schema.yaml
	python3 tools/patch_wubi_code_hint.py data/plum/wubi86_jidian.schema.yaml

deps: librime data

# --- Xpier 用户流：clone 回来自己装（完整步骤见 README）---
#   make && make test && make install
# make 第一步 bootstrap 是 requirements.sh --yes：缺 brew 包/子模块/码表就直接装，
# 不问（Xcode 装不上、brew 要密码这两处还是会停下来等人）。
# requirements 是交互式版，requirements-check 是只查版（CI 用）。
# dist 是本机打包（含自检），install 装到 ~/Library（必须本人执行），
# check 只读自检，probe 不装机看引擎（人工看），test 是 probe 断言版（机器判）。
# tools 是源码重编的小工具。
.PHONY: tools dist install install-user check probe test bootstrap requirements requirements-check doctor

KEYS ?= tffu tzfu zni

requirements:
	bash scripts/requirements.sh

bootstrap:
	bash scripts/requirements.sh --yes

requirements-check:
	bash scripts/requirements.sh </dev/null

doctor:
	bash scripts/doctor.sh

tools: tools/rime_probe tools/tis-name

tools/tis-name: tools/tis-name.swift
	swiftc -o tools/tis-name tools/tis-name.swift -framework Carbon

# 探针轨 librime（动态库，插件静态合并）：只给 rime_probe 链接用，
# 和 App 轨（build/，插件外置，随包发布）是两套目录，互不干扰。
# 顺序：先 make librime（备好 deps 里的 opencc 等），再编这个。
librime/build-rime/lib/librime.1.dylib:
	cd librime && cmake . -Bbuild-rime \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DBUILD_MERGED_PLUGINS=ON \
		-DENABLE_EXTERNAL_PLUGINS=OFF
	$(MAKE) -C librime/build-rime rime -j8

librime-probe: librime/build-rime/lib/librime.1.dylib

tools/rime_probe: tools/rime_probe.c librime-probe
	clang -O1 -o tools/rime_probe tools/rime_probe.c -Ilibrime/src \
		-Llibrime/build-rime/lib -lrime \
		-Wl,-rpath,$(CURDIR)/librime/build-rime/lib \
		-Wl,-rpath,$(CURDIR)/librime/deps/opencc/build/src

dist: debug
	bash scripts/package.sh

install-user:
	bash scripts/install.sh

# test 不装机：dist 里的包 + probe 跑矩阵 + python 断言（tffu=等、tzfu=z键、zni=反查）。
# dist 不存在就直说先跑 make，不静默触发大构建。
test: tools
	@if [ ! -d "dist/Xpier.app" ]; then echo "  dist 里没包，先跑 make"; exit 1; fi
	./tools/rime_probe "$(CURDIR)/dist/Xpier.app/Contents/SharedSupport" /tmp/probe-test wubi86_jidian tffu tzfu zni > /tmp/probe-test.log 2>&1 || true
	python3 tools/check_probe.py /tmp/probe-test.log

check:
	@echo "== 输入法进程 =="
	@pgrep -x Xpier >/dev/null 2>&1 && echo "  运行中（pid $$(pgrep -x Xpier | tr '\n' ' ')）" || echo "  未运行（切到本输入法会自动拉起）"
	@echo "== 已安装的包 =="
	@stat -f "  二进制构建时间：%Sm" -t "%m-%d %H:%M:%S" "$$HOME/Library/Input Methods/Xpier.app/Contents/MacOS/Xpier" 2>/dev/null || echo "  未安装"
	@echo "== 用户码表编译产物（缺了就打不出中文） =="
	@for f in wubi86_jidian.prism.bin wubi86_jidian.table.bin wubi86_jidian.reverse.bin wubi86_jidian.schema.yaml; do \
	  if [ -f "$$HOME/Library/Xpier/build/$$f" ]; then stat -f "  $$f: %z 字节，%Sm" -t "%m-%d %H:%M:%S" "$$HOME/Library/Xpier/build/$$f"; \
	  else echo "  $$f: 缺失（切回本输入法等重建，约十几秒，再跑一次 make check）"; fi; \
	done

probe: tools/rime_probe
	./tools/rime_probe "$(CURDIR)/dist/Xpier.app/Contents/SharedSupport" /tmp/probe-xpier wubi86_jidian $(KEYS)

ifdef ARCHS
BUILD_SETTINGS += ARCHS="$(ARCHS)"
BUILD_SETTINGS += ONLY_ACTIVE_ARCH=NO
_=$() $()
export CMAKE_OSX_ARCHITECTURES = $(subst $(_),;,$(ARCHS))
endif

ifdef MACOSX_DEPLOYMENT_TARGET
BUILD_SETTINGS += MACOSX_DEPLOYMENT_TARGET="$(MACOSX_DEPLOYMENT_TARGET)"
endif

BUILD_SETTINGS += COMPILER_INDEX_STORE_ENABLE=YES

release: $(DEPS_CHECK) xpier-patches
	mkdir -p $(DERIVED_DATA_PATH)
	bash package/add_data_files
	xcodebuild -project Squirrel.xcodeproj -configuration Release -scheme Squirrel -derivedDataPath $(DERIVED_DATA_PATH) $(BUILD_SETTINGS) build

debug: $(DEPS_CHECK) xpier-patches
	mkdir -p $(DERIVED_DATA_PATH)
	bash package/add_data_files
	xcodebuild -project Squirrel.xcodeproj -configuration Debug -scheme Squirrel -derivedDataPath $(DERIVED_DATA_PATH)  $(BUILD_SETTINGS) build

.PHONY: sparkle copy-sparkle-framework

$(SPARKLE_FRAMEWORK):
	@if [ -f Sparkle/Sparkle.xcodeproj/project.pbxproj ]; then echo "Sparkle 源码已在，跳过 submodule 更新"; \
	elif [ -d .git ]; then git submodule update --init --recursive Sparkle; \
	else echo "错误：Sparkle 源码不在且不在 git 树里（快照包没解全？删掉重解一次）"; exit 1; fi
	$(MAKE) sparkle

sparkle:
	xcodebuild -project Sparkle/Sparkle.xcodeproj -configuration Release $(BUILD_SETTINGS) build
	$(MAKE) copy-sparkle-framework

package/generate_keys:
	xcodebuild -project Sparkle/Sparkle.xcodeproj -scheme generate_keys -configuration Release -derivedDataPath Sparkle/build $(BUILD_SETTINGS) build
	cp Sparkle/build/Build/Products/Release/generate_keys package/

package/sign_update:
	xcodebuild -project Sparkle/Sparkle.xcodeproj -scheme sign_update -configuration Release -derivedDataPath Sparkle/build $(BUILD_SETTINGS) build
	cp Sparkle/build/Build/Products/Release/sign_update package/

copy-sparkle-framework:
	mkdir -p Frameworks
	cp -RP Sparkle/build/Release/Sparkle.framework Frameworks/

clean-sparkle:
	rm -rf Frameworks/* > /dev/null 2>&1 || true
	rm -rf Sparkle/build > /dev/null 2>&1 || true

.PHONY: package archive

$(PACKAGE):
ifdef DEV_ID
	bash package/sign_app "$(DEV_ID)" "$(DERIVED_DATA_PATH)"
endif
	bash package/make_package "$(DERIVED_DATA_PATH)"
ifdef DEV_ID
	productsign --sign "Developer ID Installer: $(DEV_ID)" package/Xpier.pkg package/Xpier-signed.pkg
	rm package/Xpier.pkg
	mv package/Xpier-signed.pkg package/Xpier.pkg
	xcrun notarytool submit package/Xpier.pkg --keychain-profile "$(DEV_ID)" --wait
	xcrun stapler staple package/Xpier.pkg
endif

package: release $(PACKAGE)

archive: package package/sign_update
	bash package/make_archive

DSTROOT = /Library/Input Methods
XPIER_APP_ROOT = $(DSTROOT)/Xpier.app

.PHONY: permission-check install-debug install-release

permission-check:
	[ -w "$(DSTROOT)" ] && [ -w "$(XPIER_APP_ROOT)" ] || sudo chown -R ${USER} "$(DSTROOT)"

install-debug: debug permission-check
	rm -rf "$(XPIER_APP_ROOT)"
	cp -R $(DERIVED_DATA_PATH)/Build/Products/Debug/Xpier.app "$(DSTROOT)"
	DSTROOT="$(DSTROOT)" RIME_NO_PREBUILD=1 bash scripts/postinstall

install-release: release permission-check
	rm -rf "$(XPIER_APP_ROOT)"
	cp -R $(DERIVED_DATA_PATH)/Build/Products/Release/Xpier.app "$(DSTROOT)"
	DSTROOT="$(DSTROOT)" bash scripts/postinstall

.PHONY: clean clean-deps

clean:
	rm -rf build dist > /dev/null 2>&1 || true
	rm build.log > /dev/null 2>&1 || true
	rm bin/* > /dev/null 2>&1 || true
	rm lib/* > /dev/null 2>&1 || true
	rm lib/rime-plugins/* > /dev/null 2>&1 || true
	rm data/plum/* > /dev/null 2>&1 || true
	rm data/opencc/* > /dev/null 2>&1 || true
	rm -f tools/rime_probe tools/tis-name > /dev/null 2>&1 || true
	rm -rf Frameworks/* > /dev/null 2>&1 || true

clean-package:
	rm -rf package/*appcast.xml > /dev/null 2>&1 || true
	rm -rf package/*.pkg > /dev/null 2>&1 || true
	rm -rf package/sign_update > /dev/null 2>&1 || true

clean-deps:
	$(MAKE) -C plum clean
	$(MAKE) -C librime clean
	$(MAKE) -C librime -f deps.mk clean || true
	rm -rf librime/dist librime/lib librime/bin librime/include librime/share > /dev/null 2>&1 || true
	rm -rf librime/deps/*/build > /dev/null 2>&1 || true
	$(MAKE) clean-sparkle
