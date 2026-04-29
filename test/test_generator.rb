# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"
require "rdoc"

class TestGenerator < Minitest::Test
  FIXTURE_ROOT = File.expand_path("fixtures/sample_rails", __dir__)

  def setup
    @output = Tempfile.new(["rails_docs", ".jsonl"])
    @output.close
  end

  def teardown
    @output.unlink if @output
  end

  def test_generator_is_registered
    assert RDoc::RDoc::GENERATORS.key?("rails_docs_ingester"),
           "Generator should be registered under :rails_docs_ingester"
    assert_equal RDoc::Generator::RailsDocsIngester,
                 RDoc::RDoc::GENERATORS["rails_docs_ingester"]
  end

  def test_emits_jsonl_for_fixture_source
    run_ingester
    records = parse_records

    assert_equal "header", records.first["type"]
    assert_equal "rails", records.first["source_slug"]
    assert_equal 1, records.first["schema_version"]

    pv = records.find { |r| r["type"] == "package_version" }
    assert pv
    assert_equal "1.0.0", pv["channel"]
    assert_equal 1, pv["major"]
    assert_equal "1.0", pv["release_series"]

    framework = records.find { |r| r["type"] == "framework" && r["slug"] == "activerecord" }
    assert framework
    assert_equal "Active Record", framework["display_name"]

    base_identity = records.find { |r|
      r["type"] == "entity_identity" && r["fqn"] == "ActiveRecord::Base"
    }
    assert base_identity
    assert_equal "class", base_identity["kind"]
    assert_equal "activerecord", base_identity["framework_slug"]

    save_identity = records.find { |r|
      r["type"] == "entity_identity" && r["fqn"] == "ActiveRecord::Persistence#save"
    }
    assert save_identity
    assert_equal "method", save_identity["kind"]
    assert_equal "instance", save_identity["scope"]

    create_identity = records.find { |r|
      r["type"] == "entity_identity" && r["fqn"] == "ActiveRecord::Persistence.create"
    }
    assert create_identity
    assert_equal "singleton", create_identity["scope"]

    save_version = records.find { |r|
      r["type"] == "entity_version" && r["fqn"] == "ActiveRecord::Persistence#save"
    }
    assert save_version
    assert_includes save_version["doc_markdown"], "Saves the record to the database"

    save_method_version = records.find { |r|
      r["type"] == "method_version" && r["fqn"] == "ActiveRecord::Persistence#save"
    }
    assert save_method_version
    assert_equal false, save_method_version["ghost"]

    save_params = records.select { |r|
      r["type"] == "method_param" && r["method_fqn"] == "ActiveRecord::Persistence#save"
    }
    assert_equal 1, save_params.size
    assert_equal "options", save_params.first["name"]
    assert_equal "keyrest", save_params.first["kind"]

    base_class_version = records.find { |r|
      r["type"] == "class_version" && r["fqn"] == "ActiveRecord::Base"
    }
    assert base_class_version

    persistence_edge = records.find { |r|
      r["type"] == "inheritance_edge" &&
        r["child_fqn"] == "ActiveRecord::Base" &&
        r["ancestor_fqn"] == "ActiveRecord::Persistence" &&
        r["relation"] == "include"
    }
    assert persistence_edge

    constant = records.find { |r|
      r["type"] == "entity_identity" && r["fqn"] == "ActiveRecord::Base::DEFAULT_PER_PAGE"
    }
    assert constant
    assert_equal "constant", constant["kind"]

    attribute = records.find { |r|
      r["type"] == "entity_identity" && r["fqn"] == "ActiveRecord::Base#name"
    }
    assert attribute
    assert_equal "attribute", attribute["kind"]
  end

  private

  def run_ingester
    Dir.mktmpdir do |tmp|
      original_argv = ARGV.dup
      ARGV.replace([
        "-q",
        "-f", "rails_docs_ingester",
        "--rails-docs-output", @output.path,
        "--rails-docs-channel", "1.0.0",
        "--rails-docs-git-ref", "v1.0.0",
        "--rails-docs-git-sha", "deadbeef",
        "--rails-docs-ord", "1000000",
        "--rails-docs-source-slug", "rails",
        "--rails-docs-source-display-name", "Ruby on Rails",
        "--rails-docs-source-github-repo", "rails/rails",
        "--op", File.join(tmp, "out"),
        FIXTURE_ROOT
      ])
      begin
        rdoc = RDoc::RDoc.new
        capture_io { rdoc.document(ARGV) }
      ensure
        ARGV.replace(original_argv)
      end
    end
  end

  def parse_records
    File.readlines(@output.path, encoding: "UTF-8").map { |line| JSON.parse(line) }
  end

  def capture_io
    require "stringio"
    out, err = $stdout, $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
  ensure
    $stdout = out
    $stderr = err
  end
end
