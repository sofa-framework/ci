import requests, zipfile, io, os
from datetime import date
import argparse


def downloadArchives(github_token, owner, repo, workflow_file, dest_directory, numbers=2, branch="master", event="schedule", os_names=['ubuntu', 'macos'] ):
    #TODO Add OS parameter which is a list of OS we want to download the binaries from. This is to enable to download those from Windows

    HEADERS = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github.v3+json"
    }

    url = f'https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflow_file}/runs?per_page={numbers}&branch={branch}&event={event}&status=success'
    print(f'Requesting from url {url}')
    res = requests.get(url)
    JS = res.json()



    absDestPath =  os.path.abspath(dest_directory)

    if int(JS['total_count']) != numbers:
        raise ValueError("Not enough binaries found")

    cat = ['latest', 'previous']
    if numbers>2:
        cat = [*cat, *( f'old_{i}' for i in range(numbers -2))]


    binaries_adress = []
    binaries_JS = []
    for i in range(numbers):
        binaries_adress.append(JS['workflow_runs'][i]['artifacts_url'])
        binaries_JS.append(requests.get(binaries_adress[i]).json())
        for j in range(int(binaries_JS[i]['total_count'])):
            if 'binaries_' in binaries_JS[i]['artifacts'][j]['name']:
                osName = binaries_JS[i]['artifacts'][j]['name'].split('-')[1].split('_')[0]
                if osName in os_names:
                    binaryName = '_'.join(binaries_JS[i]['artifacts'][j]['name'].split('-')[1].split('_')[:2])
                    binaryAdress = binaries_JS[i]['artifacts'][j]['archive_download_url']
                    binaryCreaterDate = date.fromisoformat(binaries_JS[i]['artifacts'][j]['updated_at'].split('T')[0])
                    binaryExpiredDate = date.fromisoformat(binaries_JS[i]['artifacts'][j]['expires_at'].split('T')[0])

                    extract_dir = f"{absDestPath}/{cat[i]}/{binaryName}"
                    if not os.path.isdir(extract_dir):
                        os.makedirs(extract_dir)



                    print(f' - Found {cat[i]} binaries for OS {osName} at adress {binaryAdress}')
                    print(f'   - Binaries are {(date.today() - binaryCreaterDate).days} days old and will expire in {(binaryExpiredDate - date.today()).days} days.')
                    print(f'   - Downloading ZIP...')
                    r = requests.get(binaryAdress,headers=HEADERS)
                    if r.ok :
                        z = zipfile.ZipFile(io.BytesIO(r.content))
                        print(f'   - Extracting it into {extract_dir}...')
                        z.extractall(extract_dir)
                    else:
                        print(f'ERROR : Request returned with error code {r.status_code}')



if __name__ == "__main__" :
    parser = argparse.ArgumentParser()
    parser.add_argument('github_token')
    parser.add_argument('dest_directory')
    parser.add_argument('--os', nargs='+', default=['ubuntu', 'macos', 'windows'])
    parser.add_argument('-n', dest='numbers', default=2, type=int)
    parser.add_argument('-b', dest='branch', default='master')
    parser.add_argument('-e', dest='event', default='schedule')
    args = parser.parse_args()

    downloadArchives(args.github_token, "sofa-framework", "sofa", "nightly-generate-binaries.yml", args.dest_directory, args.numbers, args.branch, args.event, args.os)

