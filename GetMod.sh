#!/bin/bash

# A POSIX variable
OPTIND=1 # Reset in case getopts has been used previously in the shell

# init vars
mods=()
mod_final=()
mod_name=""
version=""
latest=1
strict=0
backup=0
replace=0
mod_dir="/"
verbose=0
timeout=2

# api vars
api_cur_call="https://api.cfwidget.com/minecraft/mc-mods/"
api_cur_down="https://media.forgecdn.net/files"
api_cur_query=".download | [.name, .version, .id]"
api_cur_val=""
api_moj_call="https://launchermeta.mojang.com/mc/game/version_manifest.json"
api_moj_entry_latest=".latest.release"
api_moj_entry_vers=".versions"
api_moj_entry_id=".id"
api_moj_val=""
mojangAPI="moj"
curseAPI="cur"

# instance vars
returnVal=""
MC_ver=""
MC_ver_maj=""
MC_ver_non=""

usage="
$0 [-h] [-n name] [-v ver] [-d dir] [-t sec] [-r] [-c] [-u] [-b] [-s] [-m] [-V]

Download Minecraft specific mods or update a folder of mods from curseforge
Specifying what MC version attempts to target the closest version

Alpha/Beta/snapshot versions not supported
    will not be updated or taken into account when searching

Currently, mod dependancies are not resolved

where:
    -h  Show this help text
    -n	Specify mod name, must be same as in mod url
            For multiple mods, surround in quotes
    -v	Specify MC version (Default: latest)
    -d	Specify a working directory
    -t  Specify Api request delay in seconds (Default: 2)
    -r	Redownload and replace mods (Default:false)
    -c	Only show changes (Default:false)
    -u	Update mods in working directory (Default:false)
    -b	backup old mod (Default: false)
    -s  Enable strict version matching (Default: false)
    -V  verbose mode
    "

log() {
    if [[ verbose -eq 1 ]]; then
        echo $@
    fi
}

newModEntry() {

    local name="$1"
    local state="$2"
    local id="$3"
    local ver="$4"
    local url="$5"

    # Is this how it's done?
    local JSONStr="
    {
        \"name\": \"$name\",
        \"success\": \"$state\",
        \"id\": \"$id\",
        \"version\": \"$ver\",
        \"download\": \"$url\"
    }"

    JSONStr=$(jq -n "$JSONStr")

    echo "New Final Mod status $JSONStr"

    mod_final[${#mod_final[@]}]="$JSONStr"
}

newModEntry "lithlium" "Fsdf" "fsd" "fsd" "fdsfs"
exit 0

while getopts "h?rcmusbVv:n:d:" opt; do
    case "$opt" in
    h | \?)
        echo "$usage"
        exit 0
        ;;
    v)
        version=$OPTARG
        log "Version: $version"
        latest=0
        ;;
    n)
        mods=($OPTARG)
        log "Mod Names: ${mods[*]}"
        ;;
    r)
        replace=1
        log "Replacing Files"
        ;;
    c)
        check=1
        log "Read only mode"
        ;;
    d)
        mod_dir=$OPTARG
        log "Directory: $mod_dir"
        ;;
    u)
        update=1 # TODO: move to higher script
        log "Updating files in directory"
        ;;
    b)
        backup=1
        log "Copying old files to /Backup"
        ;;
    b)
        strict=1
        log "Versioning set to strict"
        ;;
    V)
        verbose=1
        log "VERBOSE MODE ENABLED"
        ;;
    esac
done
shift $((OPTIND - 1)) # somthin somthin, I dunno

if [[ -z "$mods" ]]; then
    echo "Mod names can't be blank!"
    echo "$usage"
    exit 0
fi

wait() {
    echo -n "Waiting for request buffer"
    for i in $(seq 1 $timeout); do
        echo -n "."
        sleep 1
    done
    echo
}

cut=0
preCut=0

cutVersion() {
    cut=0
    preCut=0
    local ver=$1
    local isRC=$3
    local isPre=$2

    for i in $(seq 1 ${#ver}); do
        if [[ "${ver:i-1:1}" == "." ]]; then
            if [[ cut -eq 1 ]]; then
                cut=$i-1
            else
                cut=1
            fi
        elif [[ (isPre -eq 1 || isRC -eq 1) && "${ver:i-1:1}" == "-" ]]; then # look for non prerelease version
            preCut=$i-1
        fi
    done

    if [[ cut -le 1 ]]; then
        if [[ preCut -eq 0 ]]; then
            cut=${#ver}
        else
            cut=$preCut
        fi
    fi

}

version_is_major=0
version_is_pre=0
version_is_rc=0
version_nonPre=""
version_major=""

verifyVer() {

    version_is_major=0
    version_is_pre=0
    version_is_rc=0
    version_nonPre=""
    version_major=""
    local ver="$1"

    log "Verifying version format"

    run=1

    if [[ $ver =~ ^1\.[1-9][0-9]* ]]; then
        if [[ $ver =~ ^1\.[1-9][0-9]*\.[1-9][0-9]*$ ]]; then
            log "Version format looks normal"
        elif [[ $ver =~ ^1\.[1-9][0-9]*$ ]]; then
            log "Version format looks normal, no minor version"
            version_is_major=1
        elif [[ $ver =~ ^1\.[1-9][0-9]*-rc[1-9][0-9]*$ ]]; then
            log "Version format looks like a release candidate"
            version_is_major=1 # assumes rcs are only for major updates
            version_is_rc=1
        elif [[ $ver =~ ^1\.[1-9][0-9]*\.[1-9][0-9]*-pre[1-9][0-9]*$ ]]; then
            log "Version format looks like a prerelease"
            version_is_pre=1
        elif [[ $ver =~ ^1\.[1-9][0-9]*-pre[1-9][0-9]*$ ]]; then
            log "Version format looks like a prerelease, no minor version"
            version_is_major=1
            version_is_pre=1
        else
            run=0
        fi
    else
        run=0
    fi

    if [[ run -eq 1 && strict -eq 0 ]]; then

        log "Getting sub versions from string"

        cutVersion $ver $version_is_pre $version_is_rc

        version_major=${ver:0:$cut}
        version_nonPre=${ver:0:$preCut}

        if [[ version_is_major -eq 0 ]]; then
            log "Major version: $version_major"
        else
            version_major="$ver"
        fi

        if [[ version_is_pre -eq 1 ]]; then
            log "Non Pre-Release Version: $version_nonPre"
        fi

        if [[ version_is_rc -eq 1 ]]; then
            log "Non Release Candidate Version: $version_nonPre"
        fi

    fi

    if [[ run -eq 0 ]]; then
        echo "Version format not valid, Alpha/Beta/snapshots not supported"
        echo "The following are valid formats, where x are numbers 0-9"
        echo "with no leading zeros"
        echo "1.x.x-prex"
        echo "1.x-rcx"
        echo "1.x.x"
        echo "1.x"
        exit 0
    fi

}

if [[ "$latest" == "0" ]]; then # Verify format of initial input version
    verifyVer "$version"
fi

log

getApi() { # TODO: throw error when curl errors
    case "$1" in
    cur)
        wait
        echo "Waiting for Curse API"
        log "Querying Curse API for mod: $2, $3"
        api_cur_val=$(curl -LsS "$api_cur_call$2/?version=$3")
        log "Api value stored"
        return 1
        ;;
    moj)
        if [[ -z "$api_moj_val" ]]; then
            echo "Waiting for Mojang API"
            log "Querying Mojang API for versions"
            api_moj_val=$(curl -sS "$api_moj_call")
            log "Mojang versions cached"
            return 1
        fi
        log "Mojang versions already cached"
        return 1
        ;;
    esac
}

getApiVal() { # TODO: Test blank/bad $2
    local val=""
    case "$1" in
    cur)
        if [[ -n "$api_cur_val" && -n "$2" ]]; then
            log "Retrieving curse api value: $2"
            val=$(jq -n "$api_cur_val" | jq "$2")
            returnVal="$val"
        fi
        ;;
    moj)
        if [[ -n "$api_moj_val" && -n "$2" ]]; then
            log "Retrieving mojang api value: $2"
            val=$(jq -n "$api_moj_val" | jq "$2")
            returnVal="$val"
        fi
        ;;
    esac
    if [[ -z "$val" || "$val" == "null" ]]; then
        returnVal=""
        log "Failed to find api value: $2"
    fi
}

# Version vars
hasVersion=0
notExact=0

matchVer() {

    local api=$1
    local focus=$2
    local selecter=$3
    local ver=$4
    local ver_non=$5
    local ver_maj=$6
    local info=$7

    returnVal=0
    hasVersion=0
    notExact=0

    log "Matching version $ver"
    getApiVal "$api" "$focus | map(select($selecter==\""$ver"\$\"))[0] | $info"
    if [[ strict -eq 0 ]]; then        # Skip if strict mode is on
        if [[ -z "$returnVal" ]]; then # An exact valid version was not found
            log "Exact version match not found"
            if [[ version_is_pre -eq 1 ]]; then    # Check all prereleases
                if [[ version_is_rc -eq 1 ]]; then # Check all releaseCans
                    log "Checking general release candidates"
                    getApiVal "$api" "$focus | map(select($selecter|test(\"^"$ver_non-rc"\")))[0] | $info"
                    if [[ -n "$returnVal" ]]; then
                        hasVersion=1
                        notExact=1
                        log "Latest release candidate found"
                    else
                        log "General release candidate not found, checking for a major release" # Major releases are checked instead of prereleases as that may cause more trouble
                        getApiVal "$api" "$focus | map(select($selecter==\""$ver_non"\"))[0] | $info"
                        if [[ -n "$returnVal" ]]; then
                            hasVersion=1
                            notExact=1
                            log "Major Release found"
                        fi
                    fi
                fi
                log "Checking general prereleases"
                getApiVal "$api" "$focus | map(select($selecter|test(\"^"$ver_non-pre"\")))[0] | $info"
                if [[ -n "$returnVal" ]]; then
                    hasVersion=1
                    notExact=1
                    log "Latest prerelease found"
                else
                    log "general prereleases not found, checking non prerelease"
                    getApiVal "$api" "$focus | map(select($selecter==\""$ver_non"\"))[0] | $info"
                    if [[ -n "$returnVal" ]]; then
                        hasVersion=1
                        notExact=1
                        log "Non prerelease found"
                    fi
                fi
            fi
            if [[ version_is_rc -eq 0 && -z "$returnVal" ]]; then # Don't check if version was found by prereleases or if looking for rcs
                log "Checking latest minor release versions"
                getApiVal "$api" "$focus | map(select($selecter|test(\"^"$ver_maj.[0-9]+"\")))[0] | $info"
                if [[ -n "$returnVal" ]]; then
                    hasVersion=1
                    notExact=1
                    log "Latest minor release version found"
                fi
            fi
        fi
    else
        log "Strict mode enabled, skipping advanced versioning"
    fi
}

getMojangVer() {
    getApi $mojangAPI

    if [[ latest -eq 1 ]]; then
        log "Defaulting to latest MC release version"
        getApiVal "moj" "$api_moj_entry_latest"
        MC_ver="$returnVal"
        log "latest release version found"
        hasVersion=1
    elif [[ -n "$1" ]]; then
        log "Verifying version $1"
        matchVer "$mojangAPI" "$api_moj_entry_vers" "$api_moj_entry_id" "$1" "$version_nonPre" "$version_major" "$api_moj_entry_id"
        MC_ver="$returnVal"
    fi

    if [[ hasVersion -eq 0 ]]; then
        echo "Failed to verify MC version"
        exit 0
    else
        MC_ver=${MC_ver:1:${#MC_ver}-2}
        log "$MC_ver"
    fi
}

mod_found_name=""
mod_found_ver=""
mod_found_url=""
foundMod=0

getModLink() {
    local name=$1
    local id=$2
    local id_maj=${id:0:4}
    local id_min=${id:4:${#id}}

    returnVal="$api_cur_down/$id_maj/$id_min/$name"
}

testModVer() {
    local ver=$1
    foundMod=0

    log "Matching mod $ver to version $MC_ver"

    if [[ "$ver" == "$MC_ver" ]]; then
        foundMod=1
        log "Mod matches version $MC_ver exactly"
    elif [[ "$ver" =~ "$MC_ver_non"-pre[1-9][0-9]*$ ]]; then
        foundMod=1
        log "Mod matches general prerelease version $MC_ver_non"
    elif [[ "$ver" =~ "$MC_ver_non"[1-9][0-9]*$ ]]; then
        foundMod=1
        log "Mod matches non prerelease version $MC_ver_non"
    elif [[ "$ver" =~ "$MC_ver_maj"[.]{0,1}[0-9]*$ ]]; then
        foundMod=1
        log "Mod matches major version $MC_ver_maj"
    else
        log "Failed to match mod to MC version"
    fi

}

getMod() {
    local mod=$1
    local ver=$2
    mod_found_name=""
    mod_found_ver=""
    mod_found_url=""

    log "Getting mod $mod version $ver"

    getApi "$curseAPI" "$mod" "$ver"
    getApiVal "$curseAPI" "$api_cur_query"
    mod_found_name="$(jq -n "$returnVal" | jq --raw-output .[0])"
    mod_found_ver="$(jq -n "$returnVal" | jq --raw-output .[1])"

    getModLink "$mod_found_name" "$(jq -n "$returnVal" | jq --raw-output .[2])"
    mod_found_url="$returnVal"

    testModVer "$mod_found_ver"
}

curl_err=0

downloadMod() {
    local name=$1
    local url=$2
    local curl_err_msg=""
    curl_err=0

    wait
    echo "Downloading mod $name"
    curl_err_msg=$(curl -sS $url -o $name)
    if [[ -z "$curl_err_msg" ]]; then
        log "$curl_err_msg"
        curl_err=1
    fi
}

getMojangVer $version

verifyVer "$MC_ver"

MC_ver_maj="$version_major"
MC_ver_non="$version_nonPre"

if [[ "$MC_ver_non" == "" ]]; then
    MC_ver_non=$MC_ver
fi

if [[ notExact -eq 1 ]]; then
    echo "Warning: Could not verify exact MC version, using version $MC_ver"
fi
log

log "Version search order"
log "Target MC Ver: $MC_ver"
log "NonPre MC Ver: $MC_ver_non"
log "Major MC Ver: $MC_ver_maj.x"

log "Beginning to check mods"

getMod $mod_name "$MC_ver"

if [[ foundMod -eq 0 ]]; then
    log "Could not find mod, retrying nonPre"
    getMod $mod_name "$MC_ver_non"
fi

if [[ foundMod -eq 0 ]]; then
    log "Could not find mod, retrying major"
    getMod $mod_name "$MC_ver_maj"
fi

if [[ foundMod -eq 1 ]]; then
    echo "Got Mod $mod_found_name   Ver: $mod_found_ver"
    log "URL: $mod_found_url"
    foundMod=1
else
    echo "Failed to find mod $mod_name $MC_ver"
fi

if [[ foundMod -eq 1 ]]; then
    downloadMod "$mod_name" "$mod_found_url"
fi
