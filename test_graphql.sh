#!/usr/bin/env bash

echo "Executing graphql"
jq --version
ORG_NAME="MYDEVVKR"

echo "=====================TEST START======================="
hasNextPage="true"
endCursor="0"
while [[ "${hasNextPage}" == "true" ]]; do
#	vars="{\"after_cursor\": \"${endCursor}\"}"
#	echo "${vars}" > q_var.json
	echo "hasNextPage=$hasNextPage"
	query_file="test_query.gql"
	if [[ "${endCursor}" == "0" ]]; then
		query_file="test_query_initial.gql"
	fi
	QUERY_TEST_TEAMS=$(jq -n \
			   --arg q "$(cat $query_file | tr -d '\n')" \
			   --arg after_cursor "${endCursor}" --arg local_org_name "${ORG_NAME}" \
			   '{ query: $q, variables: {after_cursor: $after_cursor, login: $local_org_name}}')
	QUERY_SAML_IDENTITY="$(echo $QUERY_TEST_TEAMS | tr -d '\n')"
#	echo $QUERY_TEST_TEAMS
	test_response=$(curl -H "Authorization: bearer $my_token" -sSLX POST --data "$QUERY_TEST_TEAMS" https://api.github.com/graphql)
#	echo "${test_response}" | jq .
	hasNextPage=false
	totalCount=$(echo ${test_response} | jq '. .data .organization .teams .totalCount')
	hasNextPage=$(echo ${test_response} | jq '. .data .organization .teams .pageInfo .hasNextPage')
	endCursor=$(echo ${test_response} | jq '. .data .organization .teams .pageInfo .endCursor' | tr -d '"')
done
echo "=====================TEST_END==================="
