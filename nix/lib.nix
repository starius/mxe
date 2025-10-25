{ lib, metadata }:

let
  inherit (metadata) host mxeTargets packages;
  repoRoot = ../.;

  ensurePackage = name:
    if packages ? ${name}
    then packages.${name}
    else throw "MXE package '${name}' not found in metadata";

  targetProfilesFor = name:
    let pkg = ensurePackage name;
    in pkg.targetProfiles or [];

  findProfile = profiles: target:
    lib.findFirst (profile: lib.elem target (profile.targets or [])) null profiles;

  getTargetMeta = name: target:
    let
      profiles = targetProfilesFor name;
      profile = findProfile profiles target;
      base = if profile == null then {} else lib.removeAttrs profile ["targets"];
    in {
      build = base.build or false;
      deps = base.deps or [];
      ooDeps = base.ooDeps or [];
      file = base.file or "";
      url = base.url or "";
      url2 = base.url2 or "";
      message = base.message or "";
    };

  parseDependency = target: dep:
    let
      trimmed = lib.strings.removeSuffix " " (lib.strings.removePrefix " " dep);
    in if trimmed == "" then null else
    let
      parts = lib.strings.splitString "~" trimmed;
      len = builtins.length parts;
    in if len <= 1 then {
      name = trimmed;
      inherit target;
    } else {
      name = builtins.elemAt parts (len - 1);
      target = lib.concatStringsSep "~" (lib.sublist 0 (len - 1) parts);
    };

  computeClosure =
    target: name:
      let
        go = visited: tgt: pkgName:
          let
            key = "${tgt}/${pkgName}";
          in if visited ? ${key} then visited else
            let
              targetMeta = getTargetMeta pkgName tgt;
              deps = (targetMeta.deps or []) ++ (targetMeta.ooDeps or []);
              parsed = lib.filter (x: x != null) (map (parseDependency tgt) deps);
              visited' = visited // { ${key} = { name = pkgName; target = tgt; }; };
            in lib.foldl' (acc: dep: go acc dep.target dep.name) visited' parsed;
      in go {} target name;

  getSourceInfo = target: name:
    let
      pkg = ensurePackage name;
      fields = pkg.fields or {};
      targetMeta = getTargetMeta name target;
      candidateUrls = [
        (targetMeta.url or "")
        (targetMeta.url2 or "")
        (fields.url or "")
        (fields.url2 or "")
      ];
      urls = lib.filter (u: u != "") candidateUrls;
      file = let
        raw = if (targetMeta.file or "") != ""
              then targetMeta.file
              else fields.file or "";
      in raw;
      checksum = fields.checksum or "";
    in if file == "" || checksum == "" || urls == []
       then null
       else {
         inherit name target file checksum;
         urls = lib.unique urls;
       };

  collectSources = deps:
    let
      add = acc: dep:
        let info = getSourceInfo dep.target dep.name;
        in if info == null then acc else acc // { ${info.file} = info; };
    in lib.foldl' add {} deps;

  nativeInputs = pkgs:
    with pkgs; [
      bash
      bison
      coreutils
      diffutils
      findutils
      gawk
      gdk-pixbuf
      gettext
      gnugrep
      gnum4
      gnumake
      gnupatch
      gnused
      gnutar
      gperf
      gzip
      intltool
      lzip
      openssl
      perl
      pkg-config
      python3
      python3Packages.mako
      ruby
      unzip
      wget
      which
      xz
      p7zip
      autoconf
      automake
      libtool
      flex
      bzip2
    ];

  mkMxePackage =
    { pkgs
    , name
    , target
    , extraArgs ? {}
    }:
    let
      closure = computeClosure target name;
      closureList = builtins.attrValues closure;
      sourcesMap = collectSources closureList;
      sourceRecords = lib.mapAttrs (fileName: info: info // {
        path = pkgs.fetchurl {
          name = fileName;
          urls = info.urls;
          sha256 = info.checksum;
        };
      }) sourcesMap;
      symlinkCommands = lib.concatMapStrings (info:
        ''
          ln -s ${info.path} pkg/${info.file}
        ''
      ) (builtins.attrValues sourceRecords);
      pkgMeta = ensurePackage name;
      fields = pkgMeta.fields or {};
      version = fields.version or "0";
      makeTarget = extraArgs.makeTarget or name;
      makeFlags = extraArgs.makeFlags or [];
      passthruExtra = extraArgs.passthru or {};
      derivationArgs = builtins.removeAttrs extraArgs [ "makeTarget" "makeFlags" "passthru" ];
      makeFlagsString = lib.concatStringsSep " " (map lib.escapeShellArg makeFlags);
    in pkgs.stdenv.mkDerivation ({
      pname = "mxe-${target}-${name}";
      inherit version;
      src = pkgs.lib.cleanSourceWith {
        src = repoRoot;
        filter = path: type: !(lib.strings.hasPrefix "${toString repoRoot}/.git" path);
      };
      nativeBuildInputs = nativeInputs pkgs;
      dontConfigure = true;
      buildPhase = ''
        runHook preBuild
        mkdir -p pkg
        mkdir -p "$TMPDIR/mxe-log"
        ${symlinkCommands}
        export MXE_NO_BACKUP_DL=1
        export MXE_TMP="$TMPDIR/mxe-tmp"
        make MXE_TARGETS=${lib.escapeShellArg target} \
             MXE_PREFIX=$out \
             PKG_DIR="$PWD/pkg" \
             LOG_DIR="$TMPDIR/mxe-log" \
             JOBS=${"$"}{NIX_BUILD_CORES:-1} \
             MXE_TMP="$MXE_TMP" \
             ${makeFlagsString} \
             ${lib.escapeShellArg makeTarget}
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        runHook postInstall
      '';
      passthru = {
        dependencyClosure = closure;
        metadata = pkgMeta;
      } // passthruExtra;
    } // derivationArgs);

  mkPackageSet = pkgs:
    let
      pkgNames = lib.attrNames packages;
      buildForTarget = target:
        let
          buildable = lib.filter (pkgName:
            let
              pkg = ensurePackage pkgName;
              pkgFields = pkg.fields or {};
              pkgType = pkgFields.type or "";
              profiles = targetProfilesFor pkgName;
              available = lib.any (profile: lib.elem target (profile.targets or [])) profiles;
              targetMeta = getTargetMeta pkgName target;
            in (available && (targetMeta.build or false)) || pkgType == "meta";
          ) pkgNames;
        in lib.genAttrs buildable (pkgName:
          mkMxePackage { inherit pkgs target name = pkgName; }
        );
    in lib.genAttrs mxeTargets buildForTarget;

in {
  inherit computeClosure mkMxePackage mkPackageSet nativeInputs repoRoot host mxeTargets packages;
}
