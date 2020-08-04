#!/bin/bash

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell

# init vars
mods=()
mod_name=""
version=""
latest=1
strict=0
backup=0
replace=0
mod_dir="/"
verbose=0

# api vars
api_cur_val="https://api.cfwidget.com/minecraft/mc-mods/"
api_cur_entry_name=".title"
api_cur_entry_vers=".versions| .[] "
api_cur_entry_id=".version"
api_cur_entry_if=".url"
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
$(basename "$FUNCNAME")[-h] [-n name] [-v ver] [-d dir] [-r] [-c] [-u] [-b] [-s] [-m] [-V]

Download Minecraft mods from curseforge
specific mods or update a folder of mods
Specifying what MC version attempts to target the closest version that is probably okay for mods

Alpha/Beta/snapshot versions not supported
    will not be updated or taken into account when searching

where:
    -h  Show this help text
    -n	Specify mod name/s (seperated by a space, mod names must be the exact name on their url)
    -v	Specify MC version (Default: latest)
    -d	Specify a working directory
    -r	Redownload and replace mods (Default:false)
    -c	Only show changes (Default:false)
    -u	Update mods in working directory (Default:false)
    -b	backup old mod (Default: false)
    -s  Enable strict version matching (Default: false)
    -V  verbose mode
    "

log(){
    if [ verbose ]; then
         echo $@
    fi
}

while getopts "h?rcmusbVv:n:d:" opt; do
    case "$opt" in
    h|\?)
        echo "$usage"
        exit 0
        ;;
    v)  version=$OPTARG
        log "Version: $version"
	    latest=0
        ;;
    n)  mod_name=$OPTARG
        log "Mod Name: $mod_name"
        ;;
	r)  replace=1
        log "Replacing Files"
        ;;
	c)  check=1
        log "Read only mode"
		;;
	d) 	mod_dir=$OPTARG
        log "Directory: $mod_dir"
		;;
	u)  update=1 # TODO: move to higher script
        log "Updating files in directory"
		;;
	b)  backup=1
        log "Copying old files to /Backup"
		;;	
	b)  strict=1
        log "Versioning set to strict"
		;;	
    V)  verbose=1
        ;;	
    esac
done
shift $((OPTIND - 1)) # somthin somthin, I dunno

log #Cleiyn

cut=0
preCut=0

cutVersion(){
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
        elif [[ ( isPre -eq 1 || isRC -eq 1 ) && "${ver:i-1:1}" == "-" ]]; then # look for non prerelease version
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

verifyVer(){

    version_is_major=0
    version_is_pre=0
    version_is_rc=0
    version_nonPre=""
    version_major=""
    local ver="$1"

    log "Verifying version format"

    run=1

    if [[ $ver =~ ^1\.[1-9][0-9]* ]]; then
        if [[ $ver =~  ^1\.[1-9][0-9]*\.[1-9][0-9]*$ ]]; then
            log "Version format looks normal"
        elif [[ $ver =~  ^1\.[1-9][0-9]*$ ]]; then
            log "Version format looks normal, no minor version"
            version_is_major=1
        elif [[ $ver =~  ^1\.[1-9][0-9]*-rc[1-9][0-9]*$ ]]; then
            log "Version format looks like a release candidate"
            version_is_major=1 # assumes rcs are only for major updates
            version_is_rc=1
        elif [[ $ver =~  ^1\.[1-9][0-9]*\.[1-9][0-9]*-pre[1-9][0-9]*$ ]]; then
            log "Version format looks like a prerelease"
            version_is_pre=1
        elif [[ $ver =~  ^1\.[1-9][0-9]*-pre[1-9][0-9]*$ ]]; then
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

getApi(){ # TODO: throw error when curl errors
    case "$1" in
    cur)
        echo "Waiting for Curse API"
        log "Querying Curse API for mod: $2, $3"
        api_cur_val=$(curl -s "$api_cur_val$2/?version=$3")
        log "Got mod Info"
        return 1
        ;;
    moj)
        if [[ -z "$api_moj_val" ]]; then
            echo "Waiting for Mojang API"
            log "Querying Mojang API for versions"
            api_moj_val=$(curl -s "$api_moj_call")
            log "Mojang versions cached"
            return 1
        fi
        log "Mojang versions already cached"
        return 1
        ;;
    esac
}

getApiVal(){ # TODO: Test blank/bad $2 
    local val=""
    case "$1" in
    cur)
        if [[ -n "$api_cur_val" && -n "$2" ]]; then
            log "Retrieving curse api value: $2"
            val=$(jq -n "$api_cur_val" | jq "$2")
            returnVal="$val"
        else
            log "Failed to find curse api value: $2"
        fi
        ;;
    moj)
        if [[ -n "$api_moj_val" && -n "$2" ]]; then
            log "Retrieving mojang api value: $2"
            val=$(jq -n "$api_moj_val" | jq "$2")
            returnVal="$val"
        else
            log "Failed to find mojang api value: $2"
        fi
        ;;
    esac
    if [[ -z "$val" || "$val" == "null" ]]; then
        returnVal=""
    fi
}

# Version vars
hasVersion=0
notExact=0

matchVer(){

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
    if [[ strict -eq 0 ]]; then # Skip if strict mode is on
        if [[ -z "$returnVal" ]]; then # An exact valid version was not found
            log "Exact version match not found"
            if [[ version_is_rc -eq 1 ]]; then # Check all releaseCans | Will only check if given version is also a releaseCan
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
            if [[ version_is_pre -eq 1 ]]; then # Check all prereleases | Will only check here if given version is also a prerelease
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

getMojangVer(){
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

getMod(){
    local mod=$1
    getApi "$curseAPI" "$mod" "$MC_ver"
    matchVer "$curseAPI" "$api_cur_entry_vers" "$api_cur_entry_id" "$MC_ver" "$MC_ver_non" "$MC_ver_maj" "$api_cur_entry_if"
    # .versions  | with_entries(select(.key|test("1.16"))) | .[] | map(select(.version|test("^1.16"))) [0]
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

log

getMod $mod_name

if [[ $hasVersion -eq 1 ]]; then
    echo "Found mod: $returnVal"
    if [[ $notExact -eq 1 ]]; then
        echo "Warning: It is not the exact version"
    fi
fi
