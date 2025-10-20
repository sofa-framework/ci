from prettytable import PrettyTable
from prettytable.colortable import ColorTable, Themes
import os
import sys



if __name__ == "__main__":

    if len(sys.argv) != 2:
        print("One input is expected, which is the tests log directory")
        exit(1)

    noraml_suf="\033[0m"
    bold_pre="\x1b[1m"
    ok_pre="\x1b[0;32m"
    fault_pre="\x1b[1;31m"
    not_ran_pre="\x1b[2m"

    tests = ['unit', 'scene', 'regression']
    table_rows = ["ran", "failed", "errors", "duration (s)"]

    logs_dir=sys.argv[1]

    #Determine which test has been ran
    results_files=[os.path.abspath(os.path.join(logs_dir, test_name + "-tests/" + test_name + "-tests_results.txt")) for test_name in tests ]
    test_ran=[os.path.isfile(res_file) for res_file in results_files ]

    #Fill table given files content. Crashes and failures are associated.
    table_content = [[0 for j in table_rows] for i in tests]
    for i in range(len(tests)):
        if test_ran[i]:
            with open(results_files[i]) as file:
                for line in file:
                    res_type = line.strip().split('_')[1].split('=')[0]
                    value = int(line.strip().split('=')[1].split('.')[0])
                    if res_type=="total":
                        table_content[i][0] += value
                    elif res_type=="disabled":
                        table_content[i][0] -= value
                    elif res_type=="crashes" or res_type=="failures" :
                        table_content[i][1] += value
                    elif res_type=="errors":
                        table_content[i][2] = value
                    elif res_type=="duration":
                        table_content[i][3] = value



    #Now build the pretty summary table
    res_table = ColorTable(theme=Themes.GLARE_REDUCTION)
    for i in range(len(tests)):
        if table_content[i][1] > 0 or table_content[i][2] > 0:
            tests[i] = fault_pre + tests[i] + noraml_suf
        elif table_content[i][0] == 0 :
            tests[i] = not_ran_pre + tests[i] + noraml_suf
        else:
            tests[i] = ok_pre + tests[i] + noraml_suf


    res_table.field_names = [bold_pre + "TESTS" + noraml_suf] + tests
    for i in range(len(table_rows)):
        res_table.add_row([table_rows[i]] + [table_content[j][i] for j in range(len(tests))])

    res_table.align[bold_pre + "TESTS" + noraml_suf] = "l"
    for test in tests:
        res_table.align[test] = "r"

    #Finaly print it
    print(res_table)








