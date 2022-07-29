# frozen_string_literal: true

require "csv"
require "octokit"
require "optparse"
require "optparse/date"

class InactiveMembersReport
  attr_accessor :organization, :members, :active_members, :repositories, :date, :filename

  SCOPES  = ["read:org", "read:user", "repo"].freeze
  COLUMNS = ["Username",
            "Email",
            "Created At",
            "Updated At"]


  def initialize(options = {})
    @client = options[:client]
    if options[:check]
      check_app
      check_scopes
      check_rate_limit
      exit 0
    end

    @skip_by = options[:skip]

    raise(OptionParser::MissingArgument) if
      options[:organization].nil? ||
      options[:date].nil?

    @date = options[:date]
    @organization = options[:organization]
    @active_members = {}
    @members = {}

    @filename = filename_with_org_name_and_date_range

    begin
      organization_members
      organization_repositories
      member_activity
    rescue StandardError => e
      error e.message + '\n'
      e.backtrace.each { |line| error line }
      error '\n'
      error "\n Encountered unspecified error while generating report...exiting \n"
      exit(1)
    end
  end

  def filename_with_org_name_and_date_range
    # Get today's date in YYYY-MM-DD
    today = Date.today.strftime("%Y-%m-%d")

    # Create filename for organization report for date range
    "reports/#{@organization}-inactive-members-#{@date}-to-#{today}.csv"
  end

  def check_app
    info "Application client/secret? #{@client.application_authenticated?}\n"
    info "Authentication Token? #{@client.token_authenticated?}\n"
  end

  def check_scopes
    info "Scopes: #{@client.scopes.join ","}\n"
  end

  def check_rate_limit
    info "Rate limit: #{@client.rate_limit.remaining}/#{@client.rate_limit.limit}\n"
  end

  def env_help
    output = <<-MSG
  Required Environment variables:
    OCTOKIT_ACCESS_TOKEN: A valid personal access token with Organzation admin priviliges
    OCTOKIT_API_ENDPOINT: A valid GitHub/GitHub Enterprise API endpoint URL (Defaults to https://api.github.com)
    MSG
    output
  end

  # helper to get an auth token for the OAuth application and a user
  def get_auth_token(login, password, otp)
    temp_client = Octokit::Client.new(login: login, password: password)
    res = temp_client.create_authorization(
      {
        idempotent: true,
        scopes: SCOPES,
        headers: { "X-GitHub-OTP" => otp }
      }
    )
    res[:token]
  end

  private

  def debug(message)
    $stderr.print message
  end

  def info(message)
    $stdout.print message
  end

  def error(message)
    $stderr.print message
  end

  def organization_members
    begin
      # get all organization members and place into an array of hashes
      check_rate_limit
      info "Finding #{@organization} members \n"
      if @skip_by
        info "Skipping first #{@skip_by} members...\n"
      else
        @skip_by = 0
      end

      @members = @client.organization_members(@organization).drop(@skip_by).collect do |member|
        member_user_data = @client.user(member["login"])

        {
          login: member["login"],
          email: member_user_data.email,
          created_at: member_user_data.created_at,
          updated_at: member_user_data.updated_at
        }
      end

      info "#{@members.length} members found.\n"
      check_rate_limit
      if @members.length == 0
        info "\nNo members to report activity on...exiting....\n"
        exit(0)
      end
    rescue StandardError => e
      error e.message + '\n'
      e.backtrace.each { |line| error line }
      error '\n'
      error "\nError fetching organization members...exiting\n"
      exit(1)
    end
  end

  def organization_repositories
    begin
      info "Gathering a list of repositories..."
      # get all repos in the organizaton and place into a hash
      @repositories = @client.organization_repositories(@organization).collect do |repo|
        repo["full_name"]
      end
      info "#{@repositories.length} repositories discovered\n"
    rescue
      error "\nError fetching list of repositories...exiting\n"
      exit(1)
    end
  end

  def commit_activity(repo)
    # get all commits after specified date and iterate
    info "...Commits"

    begin
      @client.commits_since(repo, @date).each do |commit|

        next if commit["author"].nil?

        @members.each do |m|
          next unless (m[:login] == commit["author"]["login"])

          if @active_members.key?(m[:login])
            @active_members[m[:login]][:commits] = true
          else
            @active_members[m[:login]] = { commits: true }
          end
        end
      end
    rescue Octokit::Conflict
      info "...no commits"
    rescue Octokit::NotFound
      # API responds with a 404 (instead of an empty set) when the `commits_since` range is out of bounds of commits.
      info "...no commits"
    end
  end

  def issue_activity(repo, date = @date)
    # get all issues after specified date and iterate
    info "...Issues"
    @client.list_issues(repo, { since: date }).each do |issue|
      # if there's no user (ghost user?) then skip this   // THIS NEEDS BETTER VALIDATION
      next if issue["user"].nil?

      @members.each do |m|
        next unless m[:login] == issue["user"]["login"]

        if @active_members.key?(m[:login])
          @active_members[m[:login]][:issues] = true
        else
          @active_members[m[:login]] = { issues: true }
        end
      end
    end
  end

  def issue_comment_activity(repo, date = @date)
    # get all issue comments after specified date and iterate
    info "...Issue comments"
    @client.issues_comments(repo, { since: date }).each do |comment|
      # if there's no user (ghost user?) then skip this   // THIS NEEDS BETTER VALIDATION
      next if comment["user"].nil?

      @members.each do |m|
        next unless m[:login] == comment["user"]["login"]

        if @active_members.key?(m[:login])
          @active_members[m[:login]][:comments] = true
        else
          @active_members[m[:login]] = { comments: true }
        end
      end
    end
  end

  def pr_activity(repo, date = @date)
    # get all pull requests after specified date and iterate
    info "...Pull Requests"
    @client.pull_requests(repo, { since: date }).each do |comment|
      # if there's no user (ghost user?) then skip this   // THIS NEEDS BETTER VALIDATION

      next if comment["user"].nil?

      @members.each do |m|
        next unless m[:login] == comment["user"]["login"]

        if @active_members.key?(m[:login])
          @active_members[m[:login]][:pull_requests] = true
        else
          @active_members[m[:login]] = { pull_requests: true }
        end
      end
    end
  end

  def member_activity
    # print update to terminal
    info "Analyzing activity for #{@members.length} members\
          and #{@repositories.length} repos for #{@organization}\n"

    initialize_file
    # for each repo
    @repositories.each_with_index do |repository, index|
      check_rate_limit
      delay_if_rate_limit_reached
      info "analyzing #{repository}"

      begin
        commit_activity(repository)
        issue_activity(repository)
        issue_comment_activity(repository)
        pr_activity(repository)

        # Write output to report file every 100 records
        if (index % 100 == 0)
          update_file(inactive_members(@members, @active_members))
        end
      rescue
        error "\nSkipping repository due to fetch error\n"
      end

      # print update to terminal
      info "...#{index + 1}/#{@repositories.length} repos completed\n"
    end

    # Clean up and update file with any members if count is less than 100
    update_file(inactive_members(@members, @active_members))


    info "No active members to report since #{@date}\n" if @active_members.size == 0
  end

  def initialize_file
    directory_name = File.dirname(@filename)
    Dir.mkdir(directory_name) unless File.exist?(directory_name)
    # open a new csv for output
    CSV.open(@filename, "wb") do |csv|

        csv << COLUMNS
    end
    info "...report file #{@filename} created\n"
  end

  def update_file(member_group)
    # open the csv to write reporet output
    CSV.open(@filename, "wb") do |csv|

      csv << COLUMNS

      member_group.each do |member_detail|
        csv << member_detail.values
      end
    end

    info "...report file #{@filename} updated\n"

  end

  def inactive_members(members, active_members)
    members.filter do |member|
      !active_members.keys.include? member[:login]
    end
  end

  def delay_if_rate_limit_reached
    # If the rate limit falls below threhshold
    # Make the script wait until after the rate limit rests (+ a 10 second buffer)
    return unless @client.rate_limit.remaining < 500

    minutes_until_rate_reset = @client.rate_limit.resets_in / 60
    info "Pausing for #{minutes_until_rate_reset} to wait for rate limit reset"
    info "Rate limit resets at: #{@client.rate_limit.resets_at}\
            ...in #{minutes_until_rate_reset} minutes  "
    sleep(@client.rate_limit.resets_in + 10)
  end
end


options = {}
OptionParser.new do |opts|
  program_description = "Find and output inactive members in an \
                 organization for a given start date"
  opts.banner = "#{$PROGRAM_NAME} - #{program_description}"

  opts.on("-c", "--check", "Check connectivity and scope") do |c|
    options[:check] = c
  end

  date_description = "Date from which to start looking for activity"
  opts.on("-d", "--date MANDATORY", Date, date_description) do |d|
    options[:date] = d.to_s
  end

  organization_description = "Organization to scan for inactive members"
  opts.on("-o", "--organization MANDATORY", String, organization_description) do |o|
    options[:organization] = o
  end

  skip_description = "Number of members to skip"
  opts.on("-s NUM", "--skip NUM", Integer, skip_description) do |s|
    options[:skip] = s
  end

  opts.on("-v", "--verbose", "More output to STDERR") do |v|
    @debug = true
    options[:verbose] = v
  end

  opts.on("-h", "--help", "Display this help") do |_h|
    puts opts
    exit 0
  end
end.parse!

stack = Faraday::RackBuilder.new do |builder|
  builder.use Octokit::Middleware::FollowRedirects
  builder.use Octokit::Response::RaiseError
  builder.use Octokit::Response::FeedParser
  builder.response :logger
  builder.adapter Faraday.default_adapter
end

Octokit.configure do |kit|
  kit.auto_paginate = true
  kit.middleware = stack if @debug
end

options[:client] = Octokit::Client.new

InactiveMembersReport.new(options)
