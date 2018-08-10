require "test_launcher/shell/history_runner"
require "test_launcher/search"
require "test_launcher/cli/input_parser"
require "test_launcher/queries"
require "test_launcher/cli/request"

module TestLauncher
  module CLI
    class MultiFrameworkQuery < Struct.new(:cli_options)
      @@mutex = Mutex.new

      def command
        # do them all at the same time!
        @count = command_finders.count
        @finished = 0
        @value = nil
        @now = Time.now.to_f

        command_finders.each do |finder|
          Thread.new do
            ex = nil

            begin
              val = finder.generic_search
            rescue => e
              ex = e
            end

            @@mutex.synchronize do
              @finished += 1
              if ex && !@exception
                @exception = ex
              elsif val && !@value
                @value = val
              end
            end
          end
        end

        while (@finished < @count && !@value && !@exception) do
          sleep(0.05)
        end

        if @exception
          raise @exception
        else
          @value
        end
      end

      def command_finders
        @command_finders ||= cli_options.frameworks.map do |framework|
          Queries::CommandFinder.new(request_for(framework))
        end
      end

      def request_for(framework)
        Request.new(
          framework: framework,
          search_string: cli_options.search_string,
          rerun: cli_options.rerun,
          run_all: cli_options.run_all,
          disable_spring: cli_options.disable_spring,
          force_spring: cli_options.force_spring,
          example_name: cli_options.example_name,
          shell: cli_options.shell,
          searcher: cli_options.searcher,
        )
      end
    end

    def self.launch(argv, env, shell: Shell::HistoryRunner.new(shell: Shell::Runner.new(log_path: '/tmp/test_launcher.log')), searcher: Search.searcher(shell))
      options = CLI::InputParser.new(
        argv,
        env
      ).parsed_options(shell: shell, searcher: searcher)

      # TODO: Well, this isn't pretty anymore...

      if options.rerun
        shell.reexec
      elsif command = MultiFrameworkQuery.new(options).command
        command = yield(command) if block_given?
        if command
          shell.exec(command)
        else
          command
        end
      else
        shell.warn "No tests found."
      end
    rescue BaseError => e
      shell.warn(e)
    end
  end
end
