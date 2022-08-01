#!/bin/bash

echo "Executing scanning alert script..."
jq --version

organization="eidikodev"

github_api_url='https://api.github.com'

#code_scanning_alert_url_array=$(curl -sSLX GET -H "Authorization: token $github_token" $github_api_url/orgs/$organization/code-scanning/alerts?per_page=100&page=2 | jq -r '.[] | .url')
#echo id, severity, name, description, security_severity_level,html_url > alert.csv
#for url in $code_scanning_alert_url_array ; do
#	alert=$(curl -sSLX GET -H "Authorization: token $github_token" "$url")
#	echo $alert
#	alert_line=$(echo $alert_line | tr -d '"' | tr -d '\')
#    alert_line=$(echo $alert | jq '.rule|[.id, .severity, .name,.description,.security_severity_level]|@csv'  )
#	html_url==$(echo $alert | jq '.html_url' | tr -d '"')
#	echo "${alert_line}, ${html_url}" >> alert.csv
#done

# curl -sSLX GET -H "Authorization: token $github_token" $github_api_url/orgs/$organization/secret-scanning/alerts?per_page=100&page=1


echo repository, html_url, secret_type, secret_type_display_name, state, resolution, secret > secret_alert.csv

START=1
total_pages=79
numbr=0
for (( c=$START; c<=$total_pages; c++ ))
do
	echo "=============Navigating Page number: $c============="
	alerts_url="${github_api_url}/orgs/${organization}/secret-scanning/alerts?per_page=100&page=${c}"
	echo "Alert URL: $alerts_url"
	all_alerts=$(curl -sSLX GET -H "Authorization: token $github_token" $alerts_url)
	all_alerts=$(echo $all_alerts | tr -d '\t' | tr -d '\')
#	echo $all_alerts
	echo "${all_alerts}" | jq -c ".[]" | while read alert;do
		api_url=$(echo $alert | jq '.url'| tr -d '"' | tr -d '\')
		html_url=$(echo $alert | jq '.html_url'| tr -d '"' | tr -d '\')
		resolution=$(echo $alert | jq '.resolution'| tr -d '"' | tr -d '\')
		secret_type=$(echo $alert | jq '.secret_type'| tr -d '"' | tr -d '\')
		secret_type_display_name=$(echo $alert | jq '.secret_type_display_name'| tr -d '"' | tr -d '\')
		secret=$(echo $alert | jq '.secret'| tr -d '"' | tr -d '\')
		repository=$(echo $alert | jq '.repository.name'| tr -d '"' | tr -d '\')
		state=$(echo $alert | jq '.state'| tr -d '"' | tr -d '\')
		set -e
		numbr=$(($numbr+1))
		echo "------------------Page: $c, Alert: $numbr----------------------"
		echo $repository
		echo $api_url
		echo $html_url
		echo "----------------------------------------"
		echo "${repository}, ${html_url}, ${secret_type}, ${secret_type_display_name}, ${state}, ${resolution}, ${secret}" >> secret_alert.csv
	done
done
