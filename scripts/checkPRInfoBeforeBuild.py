#!python

import os, re, requests

GITHUB_TOKEN = os.getenv('GITHUB_TOKEN')
PR_NUMBER = os.getenv('PR_NUMBER')


if (not GITHUB_TOKEN) or (not PR_NUMBER):
    print("Error: Missing required environment variables.")
    if (not GITHUB_TOKEN):
        print("     - Missing GITHUB_TOKEN")
    if (not PR_NUMBER):
        print("     - Missing PR_NUMBER")
    exit(1)


# GitHub API base URL
API_URL = f"https://api.github.com/repos/bakpaul/sofa"

# Headers for authentication
HEADERS = {
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "Accept": "application/vnd.github.v3+json"
}


# Flags to determine actions
to_review_or_ready_label_found = False
is_draft_pr = False
with_all_tests_found = False
force_full_build_found = False

# ========================================================================

# Check PR labels
def check_labels():
    global to_review_or_ready_label_found
    labels_url = f"{API_URL}/issues/{PR_NUMBER}/labels"
    response = requests.get(labels_url, headers=HEADERS)

    if response.status_code != 200:
        print(f"Failed to fetch labels: {response.status_code}")
        exit(1)

    labels = [label['name'].lower() for label in response.json()]
    print(f"Labels found: {labels}.")

    if ("pr: status to review" in labels) or ("pr: status ready" in labels):
        to_review_or_ready_label_found = True
        print("PR is marked as 'to review' or 'ready'.")
    else:
        print(f"Flag to review has not been found. CI will stop.")
        exit(1)


# ========================================================================

# Check the PR draft status
def check_if_draft():
    global is_draft_pr
    pr_url = f"{API_URL}/pulls/{PR_NUMBER}"
    response = requests.get(pr_url, headers=HEADERS)

    if response.status_code != 200:
        print(f"Failed to fetch pull request details: {response.status_code}")
        exit(1)

    pr_data = response.json()
    is_draft_pr = pr_data.get('draft', False)

    if is_draft_pr:
        print("The pull request is a draft. The Bash script will not run.")


# ========================================================================

# Check PR comments for "[with-all-tests]" and "[force-full-build]"
def check_body_for_tags():
    global with_all_tests_found
    global force_full_build_found
    pr_url = f"{API_URL}/pulls/{PR_NUMBER}"
    response = requests.get(pr_url, headers=HEADERS)

    if response.status_code != 200:
        print(f"Failed to fetch pull request details: {response.status_code}")
        exit(1)

    # Extract the PR description and look for [with-all-tests] and [force-full-build] patterns
    body_lines = response.json().get("body", "").splitlines()

    if any("[with-all-tests]" in line for line in body_lines):
        with_all_tests_found = True
        print("[with-all-tests] found in pr body.")
    if any("[force-full-build]" in line for line in body_lines):
        force_full_build_found = True
        print("[force-full-build] found in pr body.")


# ========================================================================

# Export all needed PR information
def export_pr_info():
    pr_url = f"{API_URL}/pulls/{PR_NUMBER}"
    response = requests.get(pr_url, headers=HEADERS)

    if response.status_code != 200:
        print(f"Failed to fetch pull request details: {response.status_code}")
        exit(1)

    pr_data = response.json()

    pr_url = str(pr_data['user']['html_url']) + "/" + str(pr_data['base']['repo']['name'])
    pr_branch_name = pr_data['head']['ref']
    pr_commit_sha = pr_data['head']['sha']

    print("PR comes from the repository: "+str(pr_url))
    print("PR branch name is: "+str(pr_branch_name))
    print("PR commit sha is: "+str(pr_commit_sha))

    with open(os.environ["GITHUB_ENV"], "a") as env_file:
        env_file.write(f"PR_OWNER_URL={pr_url}\n")
        env_file.write(f"PR_BRANCH_NAME={pr_branch_name}\n")
        env_file.write(f"PR_COMMIT_SHA={pr_commit_sha}\n")
    
    return pr_commit_sha

    ## TODO : pr_data.get('mergeable', False) could also let us know if it is mergeable


# ========================================================================

# Extract repositories from ci-depends-on
def extract_ci_depends_on():
    dependency_dict = {}
    is_merged_dict = {}

    pr_url = f"{API_URL}/pulls/{PR_NUMBER}"
    response = requests.get(pr_url, headers=HEADERS)

    if response.status_code != 200:
        print(f"Failed to fetch pull request details: {response.status_code}")
        exit(1)

    pr_data = response.json()

    # Extract the PR description and look for [ci-depends-on ...] patterns
    pr_body = pr_data.get("body", "")
    ci_depends_on = []

    # Search in each line for the pattern "[ci-depends-on ...]"
    for line in pr_body.splitlines():
        match = re.search(r'\[ci-depends-on (.+?)\]', line)
        if match:
            dependency = match.group(1).strip()
            ci_depends_on.append(dependency)
            print(f"Found ci-depends-on dependency: {dependency}")

            # Ensure the URL is in the expected dependency format, e.g. https://github.com/sofa-framework/Sofa.Qt/pull/6
            parts = dependency.split('/')
            if len(parts) != 7 or parts[0] != 'https:' or parts[1] != '' or parts[2] != 'github.com':
                print(f"Invalid URL ci-depends-on format: {dependency}")
                exit(1)

            owner = parts[3]
            repo = parts[4]
            pull_number = parts[6]
            dependency_request_url = f"https://api.github.com/repos/{owner}/{repo}/pulls/{pull_number}"

            response = requests.get(dependency_request_url, headers=HEADERS)

            if response.status_code != 200:
                print(f"Failed to fetch pull request details: {response.status_code}")
                exit(1)

            dependency_pr_data = response.json()

            key = dependency_pr_data['base']['repo']['name'] #Sofa.Qt
            repo_url = dependency_pr_data['head']['repo']['html_url'] #https://github.com/{remote from which pr comes}/Sofa.Qt
            branch_name = dependency_pr_data['head']['ref'] #my_feature_branch
            is_merged = dependency_pr_data['state'] == "closed"

            dependency_dict[key] = {
                "repo_url": repo_url,
                "branch_name": branch_name,
                "pr_url": f"https://github.com/{owner}/{repo}/pull/{pull_number}", 
            }

            is_merged_dict[key] = is_merged

        match = re.search(r'\[with-all-tests\]', line)
        if match:
            with_all_tests_found = True
    return dependency_dict, is_merged_dict


def publish_github_message(message, prNB):
    """
    Publish a comment message on a GitHub pull request.
    Args:
        message (str): The message to post.
        prNB (str or int): The pull request number.
    """
    url = f"{API_URL}/issues/{prNB}/comments"
    payload = {"body": message}

    response = requests.post(url, headers=HEADERS, json=payload)

    if response.status_code == 201:
        print(f"✅ Comment successfully posted to PR #{prNB}")
        return response.json()
    else:
        print(f"❌ Failed to post comment to PR #{prNB}")
        print(f"Status: {response.status_code} | Response: {response.text}")
        return None
    
def update_action_status(statusesUrl, context, state, description, target_url=None):
    payload = {"context": context, "state": state, "description": description}
    if target_url is not None:
        payload["target_url"] = target_url
    response = requests.post(statusesUrl, headers=HEADERS, json=payload)
    if response.status_code == 201:
        print(f"✅ Status correctly updated")
        return response.json()
    else:
        print(f"❌ Failed to update status")
        print(f"Status: {response.status_code} | Response: {response.text}")
        return None
    return

def check_ci_depends_on(pr_sha, dependency_dict = None, is_merged_dict = None):
    if dependency_dict is None or is_merged_dict is None:
        dependency_dict, is_merged_dict = extract_ci_depends_on()
    message = "**[ci-depends-on]** detected."
    
    if len(dependency_dict) == 0:
        update_action_status(f"{API_URL}/statuses/{pr_sha}", "[ci-depends-on]", "success", "No dependency found in description.")
        return 
    
    PRReady = True
    OnePRMerged = False
    for key in is_merged_dict:
        PRReady = PRReady and is_merged_dict[key]
        OnePRMerged = OnePRMerged or is_merged_dict[key]
    
    if PRReady:
        message += "\n\n All dependencies are merged/closed. Congrats! :+1:"
        update_action_status(f"{API_URL}/statuses/{pr_sha}", "[ci-depends-on]", "success", "Dependencies are OK.")
    else:
        message += "\n\n To unlock the merge button, you must"
        for key in dependency_dict:
            if not is_merged_dict[key]:
                fixedDepName = key.upper().replace('.','_')
                flag_repository="-D" + f"{fixedDepName}" + f"_GIT_REPOSITORY='{dependency_dict[key]["repo_url"]}'"
                flag_tag="-D" + f"{fixedDepName}" + f"_GIT_TAG='{dependency_dict[key]["branch_name"]}'"
                message += f"\n- **Merge or close {dependency_dict[key]["pr_url"]}**\n_For this build, the following CMake flags will be set_\n{flag_repository}\n{flag_tag}"

        if OnePRMerged:
            message += "\n\n Already satisfied dependencies : "
            for key in dependency_dict:
                if  is_merged_dict[key]:
                    message += f"\n- {dependency_dict[key]["pr_url"]}"

        update_action_status(f"{API_URL}/statuses/{pr_sha}", "[ci-depends-on]", "failure", "Please follow instructions in comments.")
    
        



    publish_github_message(message, PR_NUMBER)



# ========================================================================
# Script core
# ========================================================================

if __name__ == "__main__":

    # Execute the checks
    check_labels()
    check_if_draft()

    # Trigger the build if conditions are met
    if to_review_or_ready_label_found and not is_draft_pr:
        # Export PR information (url, name, sha)
        pr_sha = export_pr_info()

        # Check compilation options in PR body
        check_body_for_tags()
        
        # Extract dependency repositories
        dependency_dict, is_merged_dict = extract_ci_depends_on()

        # Publish ci depends on message and set action status
        check_ci_depends_on(pr_sha, dependency_dict=dependency_dict, is_merged_dict=is_merged_dict)

        # Export all environment variables specific to pull-requests
        with open(os.environ["GITHUB_ENV"], "a") as env_file:
            env_file.write(f"WITH_ALL_TESTS={with_all_tests_found}\n")
            env_file.write(f"FORCE_FULL_BUILD={force_full_build_found}\n")

            ci_depends_on_str = f"{dependency_dict}".replace("'", "\\\"")
            env_file.write(f"CI_DEPENDS_ON={ci_depends_on_str}\n")
            env_file.write(f'SH_BUILDER_OS=["sh-ubuntu_gcc_release","sh-fedora_clang_release","sh-macos_clang_release"]')
            env_file.write(f'PIXI_BUILDER_OS=["windows-latest"]')


    # ========================================================================
