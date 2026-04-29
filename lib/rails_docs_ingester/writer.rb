# frozen_string_literal: true

require "json"
require "set"

module RailsDocsIngester
  # Walks an RDoc::Store and emits JSONL records to an IO. The records match
  # the contract consumed by the rails-docs app's Loader.
  class Writer
    SCHEMA_VERSION = 1

    FRAMEWORK_SLUGS = %w[
      activesupport activerecord activemodel actionpack actionview actionmailer
      activejob actioncable activestorage actionmailbox actiontext railties
    ].freeze

    FRAMEWORK_DISPLAY_NAMES = {
      "activesupport" => "Active Support",
      "activerecord" => "Active Record",
      "activemodel" => "Active Model",
      "actionpack" => "Action Pack",
      "actionview" => "Action View",
      "actionmailer" => "Action Mailer",
      "activejob" => "Active Job",
      "actioncable" => "Action Cable",
      "activestorage" => "Active Storage",
      "actionmailbox" => "Action Mailbox",
      "actiontext" => "Action Text",
      "railties" => "Railties"
    }.freeze

    def initialize(io, store, options)
      @io = io
      @store = store
      @options = options
      @emitted_identities = Set.new
    end

    def write_all
      write_header
      write_package_version
      write_frameworks
      write_entity_identities
      write_external_identity_stubs
      write_entity_versions
      write_inheritance_edges
    end

    private

    # Header

    def write_header
      emit(
        type: "header",
        source_slug: source_slug,
        source_display_name: @options.rails_docs_source_display_name,
        source_github_repo: @options.rails_docs_source_github_repo,
        schema_version: SCHEMA_VERSION
      )
    end

    # Package version

    def write_package_version
      emit({
        type: "package_version",
        channel: @options.rails_docs_channel,
        git_ref: @options.rails_docs_git_ref,
        git_sha: @options.rails_docs_git_sha,
        ord: @options.rails_docs_ord
      }.merge(parse_version(@options.rails_docs_channel)))
    end

    # Frameworks

    def write_frameworks
      seen = Set.new
      classes_and_modules.each do |klass|
        slug = framework_slug_for(klass)
        next unless slug
        next if seen.include?(slug)
        seen << slug
        emit(type: "framework", slug: slug, display_name: FRAMEWORK_DISPLAY_NAMES.fetch(slug, slug.capitalize))
      end
    end

    # Entity identities

    def write_entity_identities
      classes_and_modules.each do |klass|
        emit_class_module_identity(klass)
        klass.constants.each { |const| emit_constant_identity(klass, const) }
        klass.attributes.each { |attr| emit_attribute_identity(klass, attr) }
        klass.method_list.each { |meth| emit_method_identity(klass, meth) }
      end
    end

    def write_external_identity_stubs
      external_refs.each do |fqn, kind|
        next if @emitted_identities.include?([fqn, kind, nil])
        emit_identity(
          fqn: fqn,
          kind: kind,
          scope: nil,
          name: fqn.split("::").last,
          parent_fqn: parent_fqn_for(fqn),
          framework_slug: nil
        )
      end
    end

    def emit_class_module_identity(klass)
      emit_identity(
        fqn: klass.full_name,
        kind: kind_for(klass),
        scope: nil,
        name: klass.name,
        parent_fqn: parent_fqn_for(klass.full_name),
        framework_slug: framework_slug_for(klass)
      )
    end

    def emit_constant_identity(klass, const)
      emit_identity(
        fqn: "#{klass.full_name}::#{const.name}",
        kind: "constant",
        scope: nil,
        name: const.name,
        parent_fqn: klass.full_name,
        framework_slug: framework_slug_for(klass)
      )
    end

    def emit_attribute_identity(klass, attr)
      emit_identity(
        fqn: "#{klass.full_name}##{attr.name}",
        kind: "attribute",
        scope: "instance",
        name: attr.name,
        parent_fqn: klass.full_name,
        framework_slug: framework_slug_for(klass)
      )
    end

    def emit_method_identity(klass, meth)
      emit_identity(
        fqn: method_fqn(klass, meth),
        kind: "method",
        scope: meth.singleton ? "singleton" : "instance",
        name: meth.name,
        parent_fqn: klass.full_name,
        framework_slug: framework_slug_for(klass)
      )
    end

    def emit_identity(record)
      key = [record[:fqn], record[:kind], record[:scope]]
      return if @emitted_identities.include?(key)
      @emitted_identities << key
      emit({type: "entity_identity"}.merge(record))
    end

    # Entity versions

    def write_entity_versions
      classes_and_modules.each do |klass|
        emit_class_module_version(klass)
        klass.constants.each { |const| emit_constant_version_records(klass, const) }
        klass.attributes.each { |attr| emit_attribute_version_records(klass, attr) }
        klass.method_list.each { |meth| emit_method_version_records(klass, meth) }
      end
    end

    def emit_class_module_version(klass)
      file_path, line = source_location_for(klass)
      emit(
        type: "entity_version",
        fqn: klass.full_name,
        kind: kind_for(klass),
        scope: nil,
        framework_slug: framework_slug_for(klass),
        visibility: "public",
        deprecated: false,
        doc_markdown: comment_text(klass.comment),
        doc_summary: doc_summary(klass.comment),
        source_path: file_path,
        source_line_start: line
      )
      if kind_for(klass) == "class"
        sc_fqn = superclass_fqn(klass)
        emit(
          type: "class_version",
          fqn: klass.full_name,
          superclass_fqn: sc_fqn,
          superclass_kind: sc_fqn ? "class" : nil
        )
      end
    end

    def emit_constant_version_records(klass, const)
      file_path, line = source_location_for(klass)
      fqn = "#{klass.full_name}::#{const.name}"
      emit(
        type: "entity_version",
        fqn: fqn,
        kind: "constant",
        scope: nil,
        framework_slug: framework_slug_for(klass),
        visibility: "public",
        doc_markdown: comment_text(const.comment),
        doc_summary: doc_summary(const.comment),
        source_path: file_path,
        source_line_start: line
      )
      emit(type: "constant_version", fqn: fqn, value_expr: const.value)
    end

    def emit_attribute_version_records(klass, attr)
      file_path, line = source_location_for(klass)
      fqn = "#{klass.full_name}##{attr.name}"
      emit(
        type: "entity_version",
        fqn: fqn,
        kind: "attribute",
        scope: "instance",
        framework_slug: framework_slug_for(klass),
        visibility: attr.visibility&.to_s || "public",
        doc_markdown: comment_text(attr.comment),
        doc_summary: doc_summary(attr.comment),
        source_path: file_path,
        source_line_start: line
      )
      emit(type: "attribute_version", fqn: fqn, scope: "instance", rw: attr.rw)
    end

    def emit_method_version_records(klass, meth)
      fqn = method_fqn(klass, meth)
      scope = meth.singleton ? "singleton" : "instance"
      file_path, line = source_location_for(meth)

      emit(
        type: "entity_version",
        fqn: fqn,
        kind: "method",
        scope: scope,
        framework_slug: framework_slug_for(klass),
        visibility: meth.visibility&.to_s || "public",
        deprecated: false,
        doc_markdown: comment_text(meth.comment),
        doc_summary: doc_summary(meth.comment),
        source_path: file_path,
        source_line_start: line,
        source_code: source_code_for(meth),
        signature_text: meth.params,
        call_seq: meth.call_seq
      )

      aliased = meth.is_alias_for
      emit(
        type: "method_version",
        fqn: fqn,
        scope: scope,
        ghost: meth.is_a?(RDoc::GhostMethod),
        aliased_fqn: aliased ? method_fqn(aliased.parent, aliased) : nil,
        aliased_scope: aliased ? (aliased.singleton ? "singleton" : "instance") : nil
      )

      params_for(meth).each_with_index do |param, idx|
        emit(
          type: "method_param",
          method_fqn: fqn,
          method_scope: scope,
          position: idx,
          name: param[:name],
          kind: param[:kind],
          default_expr: param[:default]
        )
      end
    end

    # Inheritance edges

    def write_inheritance_edges
      classes_and_modules.each do |klass|
        sc_fqn = superclass_fqn(klass)
        if sc_fqn
          emit(
            type: "inheritance_edge",
            child_fqn: klass.full_name,
            child_kind: kind_for(klass),
            ancestor_fqn: sc_fqn,
            ancestor_kind: "class",
            relation: "superclass",
            position: nil
          )
        end

        emit_module_edges(klass, klass.includes, "include")
        emit_module_edges(klass, klass.extends, "extend")
      end
    end

    def emit_module_edges(klass, references, relation)
      references.each_with_index do |ref, idx|
        ancestor_fqn = include_target_fqn(ref)
        next unless ancestor_fqn
        emit(
          type: "inheritance_edge",
          child_fqn: klass.full_name,
          child_kind: kind_for(klass),
          ancestor_fqn: ancestor_fqn,
          ancestor_kind: "module",
          relation: relation,
          position: idx
        )
      end
    end

    # Helpers

    def emit(record)
      @io.puts JSON.generate(record.compact)
    end

    def classes_and_modules
      @store.all_classes_and_modules
    end

    def kind_for(klass)
      case klass
      when RDoc::NormalModule then "module"
      else "class"
      end
    end

    def parent_fqn_for(fqn)
      parts = fqn.to_s.split("::")
      return nil if parts.size <= 1
      parts[0..-2].join("::")
    end

    def superclass_fqn(klass)
      return nil if klass.is_a?(RDoc::NormalModule)
      sc = klass.superclass
      return nil unless sc
      sc.is_a?(String) ? sc : sc.full_name
    rescue NoMethodError
      nil
    end

    def include_target_fqn(ref)
      mod = ref.module
      return ref.name if mod.is_a?(String) || mod.nil?
      mod.full_name
    end

    def method_fqn(klass, meth)
      separator = meth.singleton ? "." : "#"
      "#{klass.full_name}#{separator}#{meth.name}"
    end

    def comment_text(comment)
      return nil unless comment
      text = comment.respond_to?(:text) ? comment.text : comment.to_s
      return nil if text.nil? || text.strip.empty?
      text
    end

    def doc_summary(comment)
      text = comment_text(comment)
      return nil unless text
      first_paragraph = text.split(/\n\n+/, 2).first
      first_paragraph&.tr("\n", " ")&.strip
    end

    def source_location_for(rdoc_object)
      file_obj = rdoc_object.respond_to?(:file) ? rdoc_object.file : nil
      file = case file_obj
             when String then file_obj
             when nil then nil
             else file_obj.respond_to?(:full_name) ? file_obj.full_name : file_obj.to_s
             end
      line = rdoc_object.respond_to?(:line) ? rdoc_object.line : nil
      [file, line]
    end

    def source_code_for(meth)
      return nil unless meth.respond_to?(:token_stream) && meth.token_stream
      meth.token_stream.map { |t| t.respond_to?(:text) ? t.text : t.to_s }.join
    rescue StandardError
      nil
    end

    def params_for(meth)
      str = meth.params.to_s.strip
      return [] if str.empty?
      str = str.sub(/\A\(/, "").sub(/\)\z/, "").strip
      return [] if str.empty?

      str.split(",").map do |seg|
        parse_param_segment(seg.strip)
      end
    end

    def parse_param_segment(seg)
      case seg
      when /\A\*\*([\w]*)\z/
        {name: $1.empty? ? "kwargs" : $1, kind: "keyrest", default: nil}
      when /\A\*([\w]*)\z/
        {name: $1.empty? ? "args" : $1, kind: "rest", default: nil}
      when /\A&([\w]+)\z/
        {name: $1, kind: "block", default: nil}
      when /\A([\w]+):\s*(.*)\z/
        {name: $1, kind: $2.empty? ? "keyreq" : "key", default: $2.empty? ? nil : $2}
      when /\A([\w]+)\s*=\s*(.+)\z/
        {name: $1, kind: "opt", default: $2}
      when /\A([\w]+)\z/
        {name: $1, kind: "req", default: nil}
      else
        {name: seg, kind: "req", default: nil}
      end
    end

    def framework_slug_for(klass)
      first_file = klass.in_files.first
      return nil unless first_file
      path = first_file.is_a?(String) ? first_file : (first_file.respond_to?(:full_name) ? first_file.full_name : nil)
      return nil unless path
      path.split("/").each do |segment|
        return segment if FRAMEWORK_SLUGS.include?(segment)
      end
      nil
    end

    def source_slug
      @options.rails_docs_source_slug || "rails"
    end

    def parse_version(channel)
      return {} unless channel
      if channel =~ /\A(\d+)\.(\d+)\.(\d+)(?:[-.]?(.*))?\z/
        result = {
          major: $1.to_i,
          minor: $2.to_i,
          patch: $3.to_i,
          release_series: "#{$1}.#{$2}"
        }
        result[:prerelease] = $4 if $4 && !$4.empty?
        result
      else
        {}
      end
    end

    # Collect all FQN references from superclass/include/extend that aren't
    # documented entities themselves. The loader needs an entity_identity row
    # for these external classes/modules (Object, Kernel, etc.) so inheritance
    # edges can resolve.
    def external_refs
      refs = Set.new
      classes_and_modules.each do |klass|
        sc = superclass_fqn(klass)
        refs << [sc, "class"] if sc
        klass.includes.each do |inc|
          fqn = include_target_fqn(inc)
          refs << [fqn, "module"] if fqn
        end
        klass.extends.each do |ext|
          fqn = include_target_fqn(ext)
          refs << [fqn, "module"] if fqn
        end
      end
      refs
    end
  end
end
