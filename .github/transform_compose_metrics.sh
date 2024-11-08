#!/bin/bash

# Define the directory containing the files
directory="../android/build/compose_metrics/"

# Find the first file that matches the pattern "*release-composables.txt"
input_file=$(find $directory -type f -name "*release-composables.txt" | head -n 1)

# Check if the input file exists.
if [ ! -f "$input_file" ]; then
    echo "Error: Input file does not exist."
    exit 1
fi


# Remove everything before fun
first_step=$(awk '{
    if ($0 ~ /^fun /) {
        print $0  # Print the line as is if it starts with fun
    } else {
        sub(/.*fun /, "fun ", $0)  # Remove everything before fun
        print $0  # Print the modified line
    }
}' $input_file)


# Filter for only unstable arguments
second_step=$(echo "$first_step" | awk '
BEGIN { RS=""; FS="\n" }  # Use empty lines as record separators

# Process each function block
{
    printFirst = 1
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^fun/) {
            # Always print the function declaration line
            print $i
            printFirst = 0
        } else if ($i !~ /^ *stable/) {
            # Print the line only if it does not start with stable (ignoring leading spaces)
            if (printFirst == 0) {
                print $i
            }
        }
    }
    if (printFirst == 0) {
        print ""  # Ensure functions are separated by a blank line
    }
}')


# Inline empty funs
third_step=$(echo "$second_step" | awk '
{
    if (/^fun .*\( *$/) {  # Detect the start of a function declaration line
        func_line = $0;  # Store the function declaration
        getline next_line  # Read the next line which should be the closing parenthesis
        if (next_line ~ /^\)/) {  # Check if the next line is just the closing parenthesis
            print func_line ")"  # Print the function declaration with closing parenthesis
        } else {
            print func_line  # Print the original function line
            print next_line  # Print the next line as it wasnt just a closing parenthesis
        }
    } else {
        print $0;  # Print all other lines that do not match the pattern
    }
}')


# Filter for only fun with arguments
forth_step=$(echo "$third_step" | awk '
/^fun.*\(\)$/ {
    # This line matches functions with no arguments; do nothing (skip)
    next
}
{
    # Print all other lines
    print $0
}')


# inline function definitions and remove 'unstable'
fifth_step=$(echo "$forth_step" | awk '
BEGIN {
    inFunc = 0;  # Flag to track if we are inside a function definition
    funcLine = "";  # To accumulate the function definition
}

/^fun / {  # When a function definition starts
    inFunc = 1;  # Set in-function flag
    funcLine = $0;  # Start accumulating the function line
    next;  # Skip to the next line
}

inFunc {
    if (/^\)/) {  # If line is the closing parenthesis
        funcLine = funcLine " " $0;  # Append to the function definition
        gsub(/unstable /, "", funcLine);  # Remove unstable keyword
        print funcLine;  # Print the inlined function definition
        inFunc = 0;  # Reset in-function flag
        funcLine = "";  # Clear the accumulated line
    } else {
        gsub(/unstable /, "", $0);  # Remove unstable keyword
        funcLine = funcLine " " $0;  # Continue accumulating the function line
    }
}

END {
    if (inFunc) {  # If the last function definition did not end
        print funcLine;  # Print whats left
    }
}')

# Transform into a table
echo "$fifth_step" | awk '
BEGIN {
    # Print the table headers
    print "| Fun name | Arguments |";
    print "|----------|-----------|";
}

{
    # Remove leading and trailing spaces
    gsub(/^ +| +$/, "", $0);
    # Replace `<...>` with ``<...>`` for Markdown code formatting
    gsub(/<[^>]*>/, "`&`", $0);
    # Extract the function name
    funcName = $0;
    sub(/\(.*/, "", funcName);
    # Extract the arguments
    args = $0;
    sub(/^[^()]*\(/, "", args);
    sub(/\).*/, "", args);
    # Output the function name and its arguments in a table format
    print "| " funcName " | " args " |";
}'

# Print total count
echo
echo "Total functions count: $(grep -c "^fun" <<< "$fifth_step")"
