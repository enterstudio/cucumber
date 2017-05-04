require "json"
require "cucumber/platform"
require "cucumber/core/ast/location"

cucumber = "bundle exec cucumber -r . --format Cucumber::Formatter::EventStream::Plugin"

## Acceptance Tests
#
# These tests work through each of the examples, running the command above,
# and comparing the actual output to that found in `expected-events.ndjson`
#
# Because some of the values in the output are timing-related, we normalize
# those values using a helper function:
#

normalize_event = lambda do |event, index|
  case event["type"]
  when "test-run-started"
    event["timestamp"] = "timestamp-goes-here"
  when "test-step-finished", "test-case-finished"
    event["result"]["duration"] = "duration-goes-here-#{index}"
  when "test-case-prepared"
    event["steps"].each_with_index do |step, index|
      if step["sourceLocation"]
        step["sourceLocation"]["uri"] = Cucumber::Core::Ast::Location.from_source_location(
          step["sourceLocation"]["uri"],
          step["sourceLocation"]["line"]
        ).file
      end
      if step["actionLocation"]
        step["actionLocation"]["uri"] = Cucumber::Core::Ast::Location.from_source_location(
          step["actionLocation"]["uri"],
          step["actionLocation"]["line"]
        ).file
      end
      event["steps"][index] = step
    end
  end
  event
end

# Because some of the output depends on the specific environment where the tests
# are run, we use a lightweight mustache template to dynamically build the right
# expected output:

# Expand templates for environment-specific values in expected events
mustache = /{{([^}]+)}}/
normalize_line = lambda do |line|
  line.gsub(mustache) { |rb| eval(rb.match(mustache)[1]) }
end

# Now we dynamically build a set of RSpec example groups for each of the examples,
# and an RSpec example for each of the expected events

describe Cucumber::Formatter::EventStream do
  describe "examples" do

    path = File.dirname(__FILE__) + "/../../../examples/*"
    examples = Dir[path].map { |path| File.expand_path(path) }

    examples.each do |example_dir|

      describe File.basename(example_dir).gsub("-", " ") do

        expected = File.read(example_dir + "/expected-events.ndjson").
          lines.
          map { |line| normalize_line[line] }.
          map { |line| JSON.parse(line) }.
          map { |event, index| normalize_event[event, index] }

        actual = Dir.chdir(example_dir) { `#{cucumber}` }.
          lines.
          map { |line| JSON.parse(line) }.
          map { |event, index| normalize_event[event, index] }

        it "emits #{expected.length} event(s) as expected" do
          expect(actual.map { |event| event["type"] }).to eq expected.map { |event| event["type"] }
        end

        expected.each_with_index do |expected_event, index|
          it "emits a `#{expected_event["type"]}` event as expected" do
            expect(actual[index]).to eq(expected_event)
          end
        end

      end

    end
  end
end
