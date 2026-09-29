import os


class Logs:
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    ORANGE = "\033[38;5;208m"
    RESET = "\033[0m"

    COLORS = {
        "PASSED": GREEN,
        "FAILED": RED,
        "CRASHED": YELLOW,
    }

    def __init__(self):
        # Enable ANSI colors in Windows cmd/PowerShell (Windows 10+)
        if os.name == "nt":
            os.system("")

    def msg_any(self, msg_type, message):
        # Known types get their color; unknown types fall back to default
        color = self.COLORS.get(msg_type, self.RESET)
        # Only the prefix is colored; the message keeps the default color
        return f"{color}[{msg_type}] {self.RESET}{message}"

    def msg_passed(self, message):
        return self.msg_any("PASSED", message)

    def msg_failed(self, message):
        return self.msg_any("FAILED", message)

    def msg_crashed(self, message):
        return self.msg_any("CRASHED", message)



class SubList(object):
    def __init__(self, origList, beginIdx, endIdx):
        self.origList = origList
        self.beginIdx = beginIdx
        self.endIdx = endIdx

        self.restartContainer()

        if(endIdx > len(origList) or endIdx < 0):
            raise IndexError("endIdx must be taken be between 0 and the length of the list")

        if(beginIdx > len(origList) - 1 or beginIdx < 0):
            raise IndexError("beginIdx must be taken be between 0 and the length of the list-1")

    def restartContainer(self):
        self.currId=self.beginIdx

    def __iter__(self):
        return self
    
    def __next__(self):

        if(self.currId == self.endIdx):
            self.restartContainer()
            raise StopIteration  # Done iterating
        self.currId += 1
        return self.origList[self.currId-1]
       
