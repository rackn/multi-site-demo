#! /usr/bin/env python
# Copyright 2020, RackN
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# pip install requests
import requests, argparse, json, urllib3, os

def main():

    catalog = { "meta": {}, "sections": { "catalog_items": {} } }
    # Argument parsing 
    parser = argparse.ArgumentParser(description="Ansible dynamic inventory via DigitalRebar")
    parser.add_argument("--items", help="Modules to Include", 
        action="store", dest="items")

    raw = requests.get("https://repo.rackn.io")

    cli_args = parser.parse_args()
    items = cli_args.items

    if raw.status_code == 200: 
        rackn = raw.json()
        catalog["meta"] = rackn["meta"]
        add = items.split(",")
        for i in rackn["sections"]["catalog_items"]:
            block = rackn["sections"]["catalog_items"][i]
            if block["Name"] in add:
                id = block["Id"]
                catalog["sections"]["catalog_items"][id] = block;

    else:
        raise IOError(raw.text)

    print(json.dumps(catalog))

if __name__ == "__main__":
    main()  
