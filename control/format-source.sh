#!/bin/bash

# Constants
styler1st_bin=stylish-haskell
styler1st_opt=--inplace
styler1st_loc=--config
styler1st_web=haskell

styler2nd_bin=brittany
styler2nd_loc=--config-file
styler2nd_opt=--write-mode=inplace
styler2nd_web=lspitzner

# Argument parsing
while getopts ":s:b:qi" opt; do
    case $opt in
        b) styler2nd_cfg="$OPTARG" ;; # Brittany
        s) styler1st_cfg="$OPTARG" ;; # Stylish-Haskell
        q) quiet_mode="yes" ;;
        i) write_mode="yes" ;;
        \?) echo "Invalid option -$OPTARG" >&2 && exit 1 ;;
    esac
done

shift "$((OPTIND - 1))"
# Now "$@" contains the rest of the arguments

# If there are one or more remaining command line arguments,
# they are the source code filepaths!
if [ "$#" -ne 0 ]; then
    source_code_paths="$@"
else
    source_code_paths='.'
fi

if [ -n "$styler1st_cfg" ]; then
    styler1st_cfg="$styler1st_loc $styler1st_cfg"
else
    styler1st_cfg=""
    if [ -z "$quiet_mode" ]; then
        echo "No configuration filepath specified for 'stylish-haskell' was specified, will use the default path"
        echo "You can manually specify the path via the argument '-s FILEPATH'"
        warned="yes"
    fi
fi

if [ -n "$styler2nd_cfg" ]; then
    styler2nd_cfg="$styler2nd_loc $styler2nd_cfg"
else
    styler2nd_cfg=""
    if [ -z "$quiet_mode" ]; then
        echo "No configuration filepath specified for 'brittany' was specified, will use the default path"
        echo "You can manually specify the path via the argument '-b FILEPATH'"
        warned="yes"
    fi
fi

if [ -n "$warned" ]; then
    echo "You can suppress warnings with the flag '-q'"
fi

# Create a temporary workspace
temp_dir=$(mktemp -d -t Haskell-Styling-XXXXXXXX)
prog_dir=$temp_dir/bin
diff_dir=$temp_dir/diff
pref_dir=$temp_dir/cabal
pack_dir=$temp_dir/cabal/package-environment
pass_1st=$temp_dir/styled.output.pass-1
pass_2nd=$temp_dir/styled.output.pass-2
pass_3rd=$temp_dir/styled.output.pass-3
pass_4th=$temp_dir/styled.output.pass-4
pass_5th=$temp_dir/styled.output.pass-5
pass_6th=$temp_dir/styled.output.pass-6
pass_7th=$temp_dir/styled.output.pass-7
pass_8th=$temp_dir/styled.output.pass-8
pass_9th=$temp_dir/styled.output.pass-9
done_out=$temp_dir/styled.output.done
mkdir $prog_dir
mkdir $diff_dir
mkdir $pref_dir
mkdir $pack_dir

download_styler () {
    tar_ext=.tar.gz
    styler_url=$(curl -s https://api.github.com/repos/$1/$2/releases/latest \
        | grep "browser_download_url" \
        | grep $tar_ext \
        | cut -d '"' -f 4
        )
    styler_tar=$temp_dir/$(basename $styler_url)
    curl --silent --location $styler_url --output $styler_tar
    tar --directory=$prog_dir --extract --file=$styler_tar --strip-components 1
    rm $styler_tar
    echo "$prog_dir/$2"
}

install_styler () {
    cabal install $1 \
        --installdir=$prog_dir \
        --install-method=copy \
        --package-env $pack_dir \
        --prefix=$pref_dir \
        --with-compiler=ghc-8.10.7
    echo "$prog_dir/$1"
}

cleanup () {
#    echo "$temp_dir"
    rm -rf $temp_dir
}

# Download stylers
styler1st=$(which $styler1st_bin || download_styler $styler1st_web $styler1st_bin)
styler2nd=$(which $styler2nd_bin ||  install_styler                $styler2nd_bin)

# Run stylers
haskell_source_files=$(find $source_code_paths -not -path "*dist-newstyle*" -a \
                              -not -path "*stack-work*" -a \
                              -type f -iregex ".*.\(hs\|hsc\|lhs\)" | sort)

while read -r file_src
do
    diff_file=$(echo "$file_src" | cut -c 3- | tr '/' ' ')
    # Ensure that imports are in "post-qualified" format
#    sed 's/import[[:blank:]]\+qualified[[:blank:]]\+\([^[:blank:]]\+\)/import \1 qualified/g' $file_src > $pass_1st
    # Apply 'styligh-haskell' first
    eval "$styler1st $styler1st_cfg $file_src > $pass_1st"
    # Apply 'brittany' second
    eval "$styler2nd $styler2nd_cfg $pass_1st > $pass_2nd"
    # Place keyword 'in' and first binding on same line if 'let' is not on the same line
    sed 's/^\([ \t]*\)in \([^[:blank:]]\)/\1in  \2/' $pass_2nd > $pass_3rd
    sed '/^[[:blank:]]\+in$/  {$!{N; s/^\([[:blank:]]\+\)in\n[[:blank:]]\+\(.*\)$/\1in  \2/; ty;P;D;:y}};' $pass_3rd > $pass_4th
    # Place keyword 'let' and first binding on same line
    sed '/^[[:blank:]]\+let$/ {$!{N; s/^\([[:blank:]]\+let\)\n[[:blank:]]\+\(.*\)$/\1 \2/;   ty;P;D;:y}};' $pass_4th > $pass_5th
    # Place first constructor *and* equal sign on a new, indented line
    sed 's/^\(data.*\)[[:blank:]]\+=\(.*\)$/\1\n    =\2/g' $pass_5th > $pass_6th
    # Collapse multiple blank lines into a single blank line
    sed ':a; /^\n*$/{ s/\n//; N; ba};' $pass_6th > $pass_7th
    # Add additional blank line above "top level bindings."
    sed '/^$/ {$!{N; /^\nimport /! {/^\nmodule /! {/^\n{-# [lL][aA][nN][gG]/! {/^\n{-# [oO][pP][tT][iI][oO][nN]/! s/^\n\([^[:blank:]].*\)$/\n\n\1/; ty;P;D;:y}}}}};' $pass_7th > $pass_8th
    # Remove the additional lines just added in the comments blocks.
    sed ':a; /{-[^\n]$/,/-}/ { /^\n*$/ { s/\n//; N; ba} };' $pass_8th > $done_out
    eval "diff $file_src $done_out > '$diff_dir/$diff_file'"
    if [ -n "$write_mode" ]; then
        mv $done_out $file_src
    fi
done <<< "$haskell_source_files"

# Evaluate differences, if any
if [ -z "$write_mode" ]; then
    reformatted_files=$(find $diff_dir -type f -size +0 | sort)
    if [ -n "$reformatted_files" ]; then
        echo "Files which were not correctly formatted:"
        while read -r file_src
        do
            echo "$file_src" \
                | sed "s/${diff_dir//\//\\/}\///g" \
                | tr ' ' '/' \
                | sed -e 's/^/  - /'
        done <<< "$reformatted_files"
        exit_error='yes'
    fi
fi

cleanup

if [ -n "$exit_error" ]; then
    exit 1
else
    exit 0
fi
