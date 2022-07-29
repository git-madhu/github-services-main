#!/usr/bin/env python3
""" client"""
import csv
import glob
from collections import OrderedDict
from typing import TextIO, Dict, Union


def main():
	users_with_email_file = "user_list_with_email.csv"
	inactive_users_filename = "reports/MYDEVVKR-*.csv"

	for filename in glob.glob(inactive_users_filename):
		print(filename)
		newfile_name = filename.replace(".csv", "-merged.csv")
		with open(newfile_name, 'w', newline='') as merged_report_csvfile:
			fieldnames = ['Username', 'Email', 'Created At', 'Updated At', 'SAML EMAIL']
			writer = csv.DictWriter(merged_report_csvfile, fieldnames=fieldnames)
			writer.writeheader()

			with open(filename, newline='') as inactive_user_csvfile:
				reader = csv.DictReader(inactive_user_csvfile)
				for row in reader:
					saml_email = ""
					with open(users_with_email_file, newline='') as users_with_email_csvfile:
						users_with_email_csvfile_reader = csv.DictReader(users_with_email_csvfile)
						email_row: Union[Dict[str, str], OrderedDict[str, str]]
						for email_row in users_with_email_csvfile_reader:
							if email_row['Login'] == row['Username']:
								print(email_row['Login'], row['Email'], row['Created At'], row['Updated At'],
									  email_row['Email'])
								saml_email = email_row['Email']
								break

					writer.writerow({"Username": row['Username'], "Email": row['Email'], "Created At": row['Created At'],
									 "Updated At": row['Updated At'], "SAML EMAIL": saml_email})


if __name__ == '__main__':
	main()
