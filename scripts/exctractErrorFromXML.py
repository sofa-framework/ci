import xml.etree.ElementTree as ET
import dataclasses
import os
import sys

if len(sys.argv) != 3:
    print("Usage : exctractErrorFromXML.py <input-dir> <output-file>")
    exit(1)


@dataclasses.dataclass
class testInfo():
    execName : str
    testSuite: str
    testName : str
    faultType : str
    message : str

def recursiveFindFaultyTestTree(container : list, tree, parent, faultType, execName, testType='None'):
    if tree.tag == "testsuite"  :
        if tree.attrib[faultType+'s'] == "0":
            return
        else:
            testType = tree.attrib["name"]
    if tree.tag == faultType:
        container.append(testInfo(testSuite=testType, testName=parent.attrib["name"], faultType=faultType, message=tree.attrib["message"], execName=execName))
    for child in tree:
        recursiveFindFaultyTestTree(container, child, tree, faultType, execName,  testType)


files = [f for f in os.listdir(sys.argv[1]) if os.path.isfile(os.path.join(sys.argv[1],f))]

faileTests = []
errorTests = []

for file in files:
    tree = ET.parse(os.path.join(sys.argv[1],file))
    subTree = tree.getroot()

    recursiveFindFaultyTestTree(faileTests,subTree,None,"failure",'.'.join(file.split('.')[:-1]))
    recursiveFindFaultyTestTree(errorTests,subTree,None,"error",'.'.join(file.split('.')[:-1]))

if len(faileTests) > 0:
    with open(sys.argv[2] + "_failures", "w") as f:
        f.write("FAILED TESTS: \n\n")
        for test in faileTests:
            f.write(f"---\n{test.execName}:\n")
            f.write(f" - Test suite: '{test.testSuite}'\n")
            f.write(f" - Test name: '{test.testName}'\n\n")
            test.message.replace('\n\n','\n')
            f.write(f"{test.message}---\n\n")

if len(errorTests) > 0:
    with open(sys.argv[2] + "_errors", "w") as f:
        f.write("TESTS WITH ERROR:\n\n---\n")
        for test in errorTests:
            f.write(f"{test.execName}:")
            f.write(f"{test.execName}:\n")
            f.write(f" - Test suite: '{test.testSuite}'\n")
            f.write(f" - Test name: '{test.testName}'\n\n")
            f.write(f"{test.message}")
