#!/bin/sh
# Copyright (c) 2019 Robin Vobruba <hoijui.quaero@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


# This installs or removes a custom git merge driver to the local repo.
#
# Please the driver to prevent merge conflicts in the generated sources.
#
# NOTE This is really only required for devs, hacking on this code-base.
# NOTE All of this gets installed into the local repo only, under ".git/",
#      meaning it is not versioned.

driver_name="go-generate"
driver_file=".git/merge-driver-go-generate"
conf_file=".git/config"
#attribs_file=".gitattributes"
attribs_file=".git/info/attributes"
hook_file=".git/hooks/pre-commit"
# Space separated list of Golang generated source files
# NOTE This variables content is repository dependent
gen_src_files="cmd/serve/assets-prod.go"
# This repo path contains the sources used as input for `go generate`
src_dir="view"
# This serves as a magic marker, marking our generated text parts
# It could be any string that is unique enough.
gen_token="go-generate-token"
this_script_file=$(basename $0)

marker_begin="# BEGIN $gen_token"
marker_end="# END $gen_token"
header_note="# NOTE Do not manually edit this section; it was generated with $this_script_file"

action="$1"
if [ "$action" = "" ]
then
	# Set the default action
	action="install"
fi
if [ "$action" != "install" -a "$action" != "remove" -a "$action" != "reinstall" ]
then
	>&2 echo "Invalid action '$action'; please choose either of: install, remove, reinstall"
	exit 1
fi
if [ "$action" = "reinstall" ]
then
	# Call ourselfs recursively
	$0 remove && $0 install
	exit $?
fi

echo "$0 action: $action ..."

# Write the merge driver script
pre_text="git merge driver file $driver_file - "
if [ -e "$driver_file" ]
then
	if [ "$action" = "install" ]
	then
		echo "$pre_text writing skipped (file already exists)"
	else
		echo -n "$pre_text removing ... "
		rm "$driver_file" \
			&& echo "done" || echo "failed!"
	fi
else
	if [ "$action" = "install" ]
	then
		echo -n "$pre_text writing ... "
		cat >> "$driver_file" << EOF
#!/bin/sh
# This is a custom merge driver (for git),
# which is supposed to be used on Golang generated sources.
#
# For details about custom git merge drivers,
# see section "Defining a custom merge driver"
# at <https://git-scm.com/docs/gitattributes>.


## Parse parameters

# %O - temporary file containing the ancestor’s version of the file in conflict
ours="\$1"

# %A - temporary file containing the current version of the file in conflict
current="\$2"
result="\$2"

# %B - temporary file containing the other branches' version of the file in conflict
theirs="\$3"

# %L - conflict-marker-size
conflict_marker_size=\$4

# %P - repo-local original path of the file in conflict
orig="\$5"


## Action!

# Gegenerate all Go sources
# NOTE This may be very ineffective if we have more then one generated files in conflict,
#      as we generate all sources, once per conflicting file!
echo "Regenerating Golang sources ('go generate') due to merge conflict in \$orig ..."
go generate
if [ \$? -ne 0 ]
then
	echo "Failed! (Regenerating Golang sources)"
	exit 1
fi
echo "Done! (Regenerating Golang sources)"

# Backup the content of the original path to a temporary file we do not care about
cp "\$orig" "\$theirs"

# Becasue we generate the file to the original path, we need to move it to the path where the result is expected
cp "\$orig" "\$result"

# Restore the content of the original path
cp "\$theirs" "\$orig"

echo "Done! (Custom-Merging conflict in \$orig)"

exit 0

EOF
		[ $? -eq 0 ] && chmod +x "$driver_file" \
			&& echo "done" || echo "failed!"
	else
		echo "$pre_text removing skipped (file does not exist)"
	fi
fi

# Configure the merge driver
pre_text="git merge driver config entry in $conf_file - "
grep -q "$marker_begin" "$conf_file" 2> /dev/null
if [ $? -eq 0 ]
then
	# Our section does exist in the conf_file
	if [ "$action" = "install" ]
	then
		echo "$pre_text writing skipped (entry already exists)"
	else
		echo -n "$pre_text removing ... "
		sed -e "/$marker_begin/,/$marker_end/d" --in-place "$conf_file" \
			&& echo "done" || echo "failed!"
	fi
else
	# Our section does NOT exist in the conf_file
	if [ "$action" = "install" ]
	then
		echo -n "$pre_text writing ... "
		cat >> "$conf_file" << EOF
$marker_begin
$header_note
[merge "$driver_name"]
	name = Regenerates Golang sources using *go generate*
	driver = .git/merge-driver-go-generate %O %A %B %L %P
$marker_end
EOF
		[ $? -eq 0 ] && echo "done" || echo "failed!"
	else
		echo "$pre_text removing skipped (entry not present)"
	fi
fi

# Apply the merge driver to the generated source file(s)
pre_text="git attributes entries to $attribs_file - "
grep -q "$marker_begin" "$attribs_file" 2> /dev/null
if [ $? -eq 0 ]
then
	# Our section does exist in the attribs_file
	if [ "$action" = "install" ]
	then
		echo "$pre_text writing skipped (section already exists)"
	else
		echo -n "$pre_text removing ... "
		sed -e "/$marker_begin/,/$marker_end/d" --in-place "$attribs_file" \
			&& echo "done" || echo "failed!"
	fi
else
	# Our section does NOT exist in the attribs_file
	if [ "$action" = "install" ]
	then
		echo "$pre_text writing ..."
		echo "$marker_begin" >> "$attribs_file"
		echo "$header_note" >> "$attribs_file"
		for gen_src in $gen_src_files
		do
			pre_text_file="$pre_text - for $gen_src - "
			echo "        writing $gen_src ... "
			echo "/$gen_src    merge=go-generate" >> "$attribs_file"
		done
		echo "$marker_end" >> "$attribs_file" \
			&& echo "    done" || echo "    failed!"
	else
		echo "$pre_text removing skipped (section not present)"
	fi
fi

# Install a git hook that runs `go generate` before committing
pre_text="git pre-commit hook code to $hook_file - "
grep -q "$marker_begin" "$hook_file" 2> /dev/null
if [ $? -eq 0 ]
then
	# Our section does exist in the hook_file
	if [ "$action" = "install" ]
	then
		echo "$pre_text writing skipped (section already exists)"
	else
		echo -n "$pre_text removing ... "
		sed -e "/$marker_begin/,/$marker_end/d" --in-place "$hook_file" \
			&& echo "done" || echo "failed!"
	fi
else
	# Our section does NOT exist in the hook_file
	if [ "$action" = "install" ]
	then
		echo -n "$pre_text writing ... "
		if [ ! -e "$hook_file" ]
		then
			# We need to write the header and make it executable,
			# if it does not exist yet.
			cat >> "$hook_file" << EOF
#!/bin/sh
# Git pre-commit hook
EOF
			[ $? -eq 0 ] && chmod +x "$hook_file"
		fi
		cat >> "$hook_file" << EOF
$marker_begin
$header_note
# Custom merge driver "go-generate" helper
if git status --porcelain | awk 'match($1, "M"){print $2}' | grep -q '^$src_dir/'
then
	go generate
	git add $gen_src_files
fi
$marker_end
EOF
		[ $? -eq 0 ] \
			&& echo "done" || echo "failed!"
	else
		echo "$pre_text removing skipped (section not present)"
	fi
fi

