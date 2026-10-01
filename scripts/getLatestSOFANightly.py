import requests, zipfile, io, os
from datetime import date
import argparse


OS_NAMES = ["ubuntu", "macos", "windows"]

class Logs:
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    ORANGE = "\033[38;5;208m"
    RESET = "\033[0m"
    CYAN = "\033[96m"

    COLORS = {
        "LOG": CYAN,
        "ERROR": RED,
        "WARNING": YELLOW,
    }

    def __init__(self):
        # Enable ANSI colors in Windows cmd/PowerShell (Windows 10+)
        if os.name == "nt":
            os.system("")

    def msg_any(self, msg_type, message):
        # Known types get their color; unknown types fall back to default
        color = self.COLORS.get(msg_type, self.RESET)
        # Only the prefix is colored; the message keeps the default color
        print(f"{color}[{msg_type}] {self.RESET}{message}")

    def msg_log(self, message):
        return self.msg_any("LOG", message)

    def msg_error(self, message):
        return self.msg_any("ERROR", message)

    def msg_warning(self, message):
        return self.msg_any("WARNING", message)


def downloadArchives(github_token, owner, repo, workflow_file, dest_directory, numbers=2, branch="master", event="schedule", os_names=['ubuntu', 'macos'] ):
    #TODO Add OS parameter which is a list of OS we want to download the binaries from. This is to enable to download those from Windows

    logs = Logs()

    HEADERS = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github.v3+json"
    }

    url = f'https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflow_file}/runs?branch={branch}&status=success'
    if event != "any":
        url += f"&event={event}"
    logs.msg_log(f'Requesting from url {url}')
    res = requests.get(url)
    JS = res.json()



    absDestPath =  os.path.abspath(dest_directory)

    if int(JS['total_count']) < numbers:
        logs.msg_error("Not enough binaries found")
        exit(1)

    cat = ['latest', 'previous']
    if numbers>2:
        cat = [*cat, *( f'old_{i}' for i in range(numbers -2))]

    downloaded = 0
    binaries_adress = []
    binaries_JS = []
    for i in range(numbers):
        binaries_adress.append(JS['workflow_runs'][i]['artifacts_url'])
        binaries_JS.append(requests.get(binaries_adress[i]).json())

        os_avail = { os_name : False for os_name in os_names }
        for j in range(int(binaries_JS[i]['total_count'])):
            if 'binaries_' in binaries_JS[i]['artifacts'][j]['name']:
                for possible_OS_name in OS_NAMES:
                    if possible_OS_name in binaries_JS[i]['artifacts'][j]['name'] and possible_OS_name in os_avail:
                        os_avail[possible_OS_name] = True

        is_this_run_suited = True
        for avail in os_avail.values():
            is_this_run_suited = is_this_run_suited and avail

        if is_this_run_suited:
            logs.msg_log(f"Run {JS['workflow_runs'][i]['html_url']} is suited for the requested OS.")
            for j in range(int(binaries_JS[i]['total_count'])):
                if 'binaries_' in binaries_JS[i]['artifacts'][j]['name']:
                    osName = None
                    for possible_OS_name in OS_NAMES:
                        if possible_OS_name in binaries_JS[i]['artifacts'][j]['name']:
                            osName = possible_OS_name
                    if osName in os_names:
                        binaryAdress = binaries_JS[i]['artifacts'][j]['archive_download_url']
                        binaryCreaterDate = date.fromisoformat(binaries_JS[i]['artifacts'][j]['updated_at'].split('T')[0])
                        binaryExpiredDate = date.fromisoformat(binaries_JS[i]['artifacts'][j]['expires_at'].split('T')[0])

                        extract_dir = f"{absDestPath}/{cat[i]}/{osName}"
                        if not os.path.isdir(extract_dir):
                            os.makedirs(extract_dir)



                        logs.msg_log(f' - Found {cat[i]} binaries for OS {osName} at adress {binaryAdress}')
                        logs.msg_log(f'   - Binaries are {(date.today() - binaryCreaterDate).days} days old and will expire in {(binaryExpiredDate - date.today()).days} days.')
                        logs.msg_log(f'   - Downloading ZIP...')
                        r = requests.get(binaryAdress,headers=HEADERS)
                        if r.ok :
                            z = zipfile.ZipFile(io.BytesIO(r.content))
                            logs.msg_log(f'   - Extracting it into {extract_dir}...')
                            z.extractall(extract_dir)

                            downloaded += 1
                        else:
                            logs.msg_error(f'Request returned with error code {r.status_code}')
        else:
            logs.msg_warning(f"Run {JS['workflow_runs'][i]['html_url']} is NOT suited for the requested OS. Missing OS are : {[os_name for os_name in os_avail if not os_avail[os_name]]}")
    if(downloaded != len(os_names) * numbers):
        logs.msg_error(f"All the requested archives couldn't be found.")
        exit(1)





if __name__ == "__main__" :
    parser = argparse.ArgumentParser(prog='getLatestSOFANightly',
                    description='Download SOFA archives from the action CI_nightly_generate_binaries.')
    parser.add_argument('github_token', help='Github token with read access to download the archives.')
    parser.add_argument('dest_directory', help='Directory in which the archives will be unziped.')
    parser.add_argument('--os', nargs='+', default=OS_NAMES, help="For which os download an archive. Any workflow run that didn't produce an archive for all the requested OS will be skipped." )
    parser.add_argument('-n', dest='numbers', default=1, type=int, help="Number of archive to download for each os. If there is not enough run that produced archives for all binaries, this call will exit 1 but will not clean the dest_directory.")
    parser.add_argument('-b', dest='branch', default='master', help="SOFA repository branch from which to download the archive.")
    parser.add_argument('-e', dest='event', choices=['any', 'schedule', 'push', 'workflow_dispatch'], default='any', help="Event to take into account. If 'any', will considere binaries that have been generated by any event like a push or a manual generation.")
    args = parser.parse_args()

    downloadArchives(args.github_token, "sofa-framework", "sofa", "CI_nightly_generate_binaries.yml", args.dest_directory, args.numbers, args.branch, args.event, args.os)

    exit(0)
