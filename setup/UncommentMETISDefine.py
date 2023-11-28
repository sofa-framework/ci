import sys
import fileinput



# Strips the newline character
for line in fileinput.input(sys.argv[1], inplace=True):
    if(("//#define REALTYPEWIDTH 32" in line) or ("//#define IDXTYPEWIDTH 32" in line)):
        print('{}'.format(line[2:]), end='')
    else:
        print('{}'.format(line), end='')

