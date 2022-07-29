#!/usr/bin/env bash

#curl -sSLX GET -H "Authorization: token $my_token" -H "Accept: application/vnd.github.v3+json" https://api.github.com/orgs/MYDEVVKR/teams
echo "Executing graphql"
jq --version
ORG_NAME="MYDEVVKR"
QUERY=$(jq -n \
           --arg q "$(cat fetch_teams.query.gql | tr -d '\n')" \
           '{ query: $q }')
fetch_teams_response=$(curl -H "Authorization: bearer $my_token" -sSLX POST --data "$QUERY" https://api.github.com/graphql)
echo "============================================"
#echo "${fetch_teams_response}" | jq .
echo "============================================"
all_teams=$(echo $fetch_teams_response | jq '. .data .organization .teams .edges')
echo "TeamName, Role, Member, Parent Team" > inactive_user.csv
echo $all_teams | jq -rc .[] | while read team;do
	team_name=$(echo $team | jq '. .node .name')
	parent_team_name=$(echo $team | jq '. .node .parentTeam .name' | tr -d '"')

	members=$(echo $team | jq '. .node .members .edges')
	echo $members | jq -rc .[] | while read member;do
		member_login=$(echo $member | jq '. .node .login' | tr -d '"')
		member_role=$(echo $member | jq '. .role' | tr -d '"')
		echo "${team_name}, ${member_role}, ${member_login}, ${parent_team_name}" >> inactive_user.csv
	done
done

echo "=====================FETCH SAML IDENTITY START======================="
hasNextPage="true"
endCursor="0"
echo "Login, Email" > user_list_with_email.csv
while [[ "${hasNextPage}" == "true" ]]; do
#	echo "hasNextPage=$hasNextPage"
	query_file="saml_identity.gql"
	if [[ "${endCursor}" == "0" ]]; then
		query_file="saml_identity_initial.gql"
	fi
	QUERY_SAML_IDENTITY=$(jq -n \
			   --arg q "$(cat $query_file | tr -d '\n')" \
			   --arg after_cursor "${endCursor}" --arg local_org_name "${ORG_NAME}" \
			   '{ query: $q, variables: {after_cursor: $after_cursor, org_name: $local_org_name}}')
	QUERY_SAML_IDENTITY="$(echo ${QUERY_SAML_IDENTITY} | tr -d '\n')"
#	echo ${QUERY_SAML_IDENTITY}
	saml_identity_response=$(curl -H "Authorization: bearer $my_token" -sSLX POST --data "${QUERY_SAML_IDENTITY}" https://api.github.com/graphql)
#	echo "${saml_identity_response}" | jq .
	hasNextPage=false
	samlIdentityProvider=$(echo ${saml_identity_response} | jq '. .data .organization .samlIdentityProvider')
	if [[ "${samlIdentityProvider}" == null ]]; then
		break
	fi
	totalCount=$(echo ${saml_identity_response} | jq '. .data .organization .samlIdentityProvider .externalIdentities .totalCount')
	hasNextPage=$(echo ${saml_identity_response} | jq '. .data .organization .samlIdentityProvider .externalIdentities .pageInfo .hasNextPage')
	endCursor=$(echo ${saml_identity_response} | jq '. .data .organization .samlIdentityProvider .externalIdentities .pageInfo .endCursor' | tr -d '"')
	all_members=$(echo ${saml_identity_response} | jq '. .data .organization .samlIdentityProvider .externalIdentities .nodes')
	echo "${all_members}" | jq -rc .[] | while read member;do
		login=$(echo $member | jq '. .user .login' | tr -d '"')
		email=$(echo $member | jq '. .samlIdentity .nameId' | tr -d '"')
		if [[ "${login}" != "null" ]]; then
			echo "${login}, ${email}" >> user_list_with_email.csv
		fi
	done
done
echo "=====================FETCH SAML IDENTITY END==================="
