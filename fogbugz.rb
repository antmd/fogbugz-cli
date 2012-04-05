#!/usr/bin/env ruby

require 'rubygems'
require 'commander/import'
require 'terminal-table'
require 'fogbugz'
require 'active_support/inflector'
require 'rconfig'

# Import configuration
RConfig.config_paths = ['#{APP_ROOT}/config']

# Define program parameters
program :name,           'FogBugz Command Line Client'
program :version,        '1.1.0'
program :description,    'Manage FogBugz cases from the command line. Ideal for batch processing.'
program :help_formatter, :compact
 
command :search do |c|
  # Definition
  c.syntax      = 'fogbugz search [query]'
  c.summary     = 'Search FogBugz for cases.'
  c.description = 'Outputs a list of cases which match the provided query, or your current case list.'
  # Options
  c.option        '--open', 'Only return open cases'
  # Examples
  c.example       'Search for a case by title',      'fogbugz search "Test Title"'
  c.example       'Search for a case by ID',         'fogbugz search 12'
  c.example       'Search for multiple cases by ID', 'fogbugz search 12,25,556'
  # Behavior
  c.action do |args, options|
    client = authenticate
    args = args || [] # Empty args defaults to returning current active case list
    # Search
    cases = if options.open then search_all(args.join) else search_open(args.join) end
    show_cases cases
  end
end

command :list do |c|
  # Definition
  c.syntax      = 'fogbugz list [type]'
  c.summary     = 'Display a list of [projects, categories, people, statuses]'
  c.description = 'Outputs the contents of the list in a easy to read format'
  # Options
  c.option        '--category ID', String, 'For statuses only, filter by a category.'
  c.option        '--resolved', 'For statuses only, only list resolved statuses.'
  # Examples
  c.example       'List all active users', 'fogbugz list people'
  # Behavior
  c.action do |args, options|
    # Defaults
    options.default :resolved => false
    options.default :category => ''

    client = authenticate

    p
    headings = [] # Used for printing a table of results
    rows = [] # Used for printing a table of results
    list_options = {}

    unless args.empty?
      case args.join
      when "statuses"
        if options.resolved
          list_options['fResolved'] = 1
        end
        unless options.category.empty?
          list_options['ixCategory'] = options.category
        end
        statuses = list("statuses", list_options)
        statuses.each do |status|
          rows << [ status['sStatus'], status['ixStatus'], status['ixCategory'] ]
        end
        print_table ['Status', 'StatusID', 'CategoryID'], rows
      else
        p "This type of list is not supported yet."
      end
    else
      p "You should specify a list type."
    end
  end
end

command :resolve do |c|
  # Definition
  c.syntax      = 'fogbugz resolve [query]'
  c.summary     = 'Resolve all cases that match a given query, and are assigned to you.'
  c.description = 'Searches for any cases that match a given criteria, and resolves any matches that belong to you.'
  # Options
  c.option        '--close', 'In addition to resolving the case, close it out.'
  c.option        '--status ID', String, 'The status with which to resolve this case. Default is 45 (Fixed).'
  # Examples
  c.example       'Resolve by title',       'fogbugz resolve "Test Title"'
  c.example       'Resolve by ID',          'fogbugz resolve 12'
  c.example       'Resolve multiple by ID', 'fogbugz resolve 12, 25, 556'
  # Behavior
  c.action do |args, options|
    # Defaults
    options.default :close => false
    options.default :status => 45 # Fixed

    client = authenticate

    p
    unless args.empty?
      # Get open cases assigned to me
      cases = search_open(args.join, nil, true)

      unless cases.empty?
        resolved = resolve cases, options.status
        p 'The following cases were resolved: ' + resolved.join
        if options.close
          closed = close cases
          p 'The following cases were closed: ' + closed.join
        end
      else
        p 'No open cases were found that match that query.'
      end
    else
      p 'You must provide a search query.'
    end
  end
end

command :close do |c|
  # Definition
  c.syntax      = 'fogbugz close [query]'
  c.summary     = 'Close all cases that match a given query, and are assigned to you.'
  c.description = 'Searches for any cases that match a given criteria, and resolves any matches that belong to you.'
  # Examples
  c.example       'Close by title',       'fogbugz close "Test Title"'
  c.example       'Close by ID',          'fogbugz close 12'
  c.example       'Close multiple by ID', 'fogbugz close 12, 25, 556'
  # Behavior
  c.action do |args, options|
    client = authenticate

    p
    unless args.empty?
      # Get open cases assigned to me that match the query
      cases = search_open(args.join, nil, true)

      unless cases.empty?
        closed = close cases
        p 'The following cases were closed: ' + closed.join
      else
        p 'No open cases were found that match that query.'
      end
    else
      p 'You must provide a search query.'
    end
  end
end

command :reopen do |c|
  # Definition
  c.syntax      = 'fogbugz reopen [query]'
  c.summary     = 'Reopen all cases that match a given query, and are assigned to you.'
  c.description = 'Searches for any cases that match a given criteria and reopens them.'
  # Examples
  c.example       'Resolve by title',       'fogbugz reopen "Test Title"'
  c.example       'Resolve by ID',          'fogbugz reopen 12'
  c.example       'Resolve multiple by ID', 'fogbugz reopen 12, 25, 556'
  # Behavior
  c.action do |args, options|
    client = authenticate

    unless args.empty?
      cases = search_closed(args.join)
      unless cases.empty?
        reopened = reopen cases
        p 'The following cases were reopened: ' + reopened.join
      else
        p 'No closed cases were found that match that query.'
      end
    else
      p 'You must provide a search query.'
    end
  end
end

private

  ###############
  # Authenticate
  # -------------
  # Authenticate fogbugz client to server. Cache auth token for reuse.
  ###############
  def authenticate
    @fogbugz_url = RConfig.fogbugz.server.address || ask("What is the URL of your FogBugz server?")
    @auth_email  = RConfig.fogbugz.user.email     || ask("What is your FogBugz email?")
    @auth_pass   = RConfig.fogbugz.user.password  || ask("What is your FogBugz password?")

    # Cache the authentication token
    if @token.nil?
      client = Fogbugz::Interface.new(:email => @auth_email, :password => @auth_pass, :uri => @fogbugz_url)
      client.authenticate
      @token = client.token
      client
    else
      client = Fogbugz::Interface.new(:token => @token, :uri => @fogbugz_url)
    end
  end

  ###############
  # Search
  # -------------
  # Execute a simple find. If query is malformed, it will return all cases that belong to the caller.
  # Params:
  #   query: A string to search for (can be a case, csv of cases, general string)
  #   columns: A comma separated list of columns to retrieve (optional)
  #   mine: A boolean flag indicating whether to return only cases that are assigned to you (optional, defaulting to false)
  ###############
  def search_all(query, columns = RConfig.fogbugz.cases.default_columns, mine = false)
    client = authenticate
    results = client.command(:search, :q => query, :cols => columns)

    unless results.nil?
      # Determine if this is a single result or many
      # and ensure that the result always an array
      cases = results['cases']['case'] || []
      if cases.is_a? Hash
        cases = [].push(cases)
      end

      # Filter for cases that belong to me if requested
      if mine
        cases.reject! {|c| c['sEmailAssignedTo'] != @auth_email }
      else
        cases
      end
    else
      []
    end
  end

  ###############
  # Search Open
  # -------------
  # Execute a simple find. Returns only cases that are active.
  # Params:
  #   query: A string to search for (can be a case, csv of cases, general string)
  #   columns: A comma separated list of columns to retrieve (optional)
  #   mine: A boolean flag indicating whether to return only cases that are assigned to you (optional, defaulting to false)
  ###############
  def search_open(query, columns = RConfig.fogbugz.cases.default_columns, mine = false)
    cases = search_all(query, columns, mine)
    cases.reject! {|c| c['fOpen'] == 'false' }
  end

  ###############
  # Search Closed
  # -------------
  # Execute a simple find. Returns only cases that are closed.
  # Params:
  #   query: A string to search for (can be a case, csv of cases, general string)
  #   columns: A comma separated list of columns to retrieve (optional)
  #   mine: A boolean flag indicating whether to return only cases that are assigned to you (optional, defaulting to false)
  ###############
  def search_closed(query, columns = RConfig.fogbugz.cases.default_columns, mine = false)
    cases = search_all(query, columns, mine)
    cases.reject! {|c| c['fOpen'] == 'true' }
  end

  ###############
  # Get List
  # -------------
  # Fetches a list of objects from FogBugz
  # Params:
  #   type: The type of object to list
  #   options: Options specific to the list being fetched. These are FogBugz query options, see the XML API for info.
  ###############
  def list(type, options = {})
    command = "list#{type.capitalize}".to_sym
    client = authenticate
    results = client.command(command, options)
    results = results[type][type.singularize] || []
  end

  ###############
  # Resolve Cases
  # -------------
  # Takes an array of cases, and resolves them.
  # Params:
  #   cases: An array of cases
  # Returns:
  #   An array of bug IDs resolved
  ###############
  def resolve(cases, status = 45)
    resolved = []
    if RConfig.fogbugz.output.progress
      progress cases do |c|
        client.command(:resolve, :ixBug => c['ixBug'], :ixStatus => status)
        resolved.push(c['ixBug'])
      end
    else
      cases.each do |c|
        client.command(:close, :ixBug => c['ixBug'], :ixStatus => status)
        resolved.push(c['ixBug'])
      end
    end

    resolved
  end

  ###############
  # Close Cases
  # -------------
  # Takes an array of cases, and closes them.
  # Params:
  #   cases: An array of cases
  # Returns:
  #   An array of bug IDs closed
  ###############
  def close(cases)
    closed = []
    if RConfig.fogbugz.output.progress
      progress cases do |c|
        client.command(:close, :ixBug => c['ixBug'])
        closed.push(c['ixBug'])
      end
    else
      cases.each do |c|
        client.command(:close, :ixBug => c['ixBug'])
        closed.push(c['ixBug'])
      end
    end

    closed
  end

  ###############
  # Reopen Cases
  # -------------
  # Takes an array of cases, and reopens them.
  # Params:
  #   cases: An array of cases
  # Returns:
  #   An array of bug IDs reopened
  ###############
  def reopen(cases)
    reopened = []
    if RConfig.fogbugz.output.progress
      progress cases do |c|
        client.command(:reopen, :ixBug => c['ixBug'])
        reopened.push(c['ixBug'])
      end
    else
      cases.each do |c|
        client.command(:reopen, :ixBug => c['ixBug'])
        reopened.push(c['ixBug'])
      end
    end

    reopened
  end

  ###############
  # Show Cases
  # -------------
  # Takes an array of cases, and either prints them to a table, or if the array is empty, prints that information
  # Params:
  #   cases: An array of cases
  ###############
  def show_cases(cases)
    p
    unless cases.empty?
      headings = ['BugID', 'Status', 'Title', 'Assigned To']
      rows = []
      cases.each do |c|
        rows << [ c['ixBug'], c['sStatus'], c['sTitle'], c['sPersonAssignedTo'] ]
      end
      print_table headings, rows
    else
      p 'No open cases were found that match your query.'
    end
  end

  ###############
  # Print Table
  # -------------
  # Takes an array of headings and an array of rows, and prints a table
  ###############
  def print_table(headings, rows)
    table = Terminal::Table.new do |t|
      :headings => headings
      :rows => rows
    end
    puts table
  end