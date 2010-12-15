require 'railroady/models_diagram'

class ModelsDatampaperDiagram < ModelsDiagram

  # Process model files
  def generate
    STDERR.print "Generating models diagram\n" if @options.verbose
    get_files.each do |f|
      begin
        process_class extract_class_name(f).constantize
      rescue Exception
        STDERR.print "Warning: exception #{$!} raised while trying to load model class #{f}\n"
      end

    end
  end

  def get_files(prefix ='')
    files = !@options.specify.empty? ? Dir.glob(@options.specify) : Dir.glob(prefix << "app/models/**/*.rb")
    files += Dir.glob("vendor/plugins/**/app/models/*.rb") if @options.plugins_models
    files -= Dir.glob(@options.exclude)
    files
  end

  def get_properties(model_klass)
    # Collect model's content columns
    # change to properties ....
    node_attr = []
    content_columns = model_klass.content_columns

    if @options.hide_magic
      # From patch #13351
      # http://wiki.rubyonrails.org/rails/pages/MagicFieldNames

      magic_fields = [
        "created_at", "created_on", "updated_at", "updated_on",
        "lock_version", "type", "id", "position", "parent_id", "lft",
        "rgt", "quote", "template"
      ]

      magic_fields << model_klass.table_name + "_count" if model_klass.respond_to? 'table_name'
      content_columns = model_klass.content_columns.select {|c| ! magic_fields.include? c.name}
    else
      content_columns = model_klass.content_columns
    end

    content_columns.each do |a|
      content_column = a.name
      content_column += ' :' + a.type.to_s unless @options.hide_types
      node_attr << content_column
    end
    node_attr
  end


  # Process a model class
  def process_class(current_class)

    STDERR.print "\tProcessing #{current_class}\n" if @options.verbose

    generated = false

    # Is current_clas derived include methods from DataMapper?
    if current_class.respond_to? 'reflect_on_all_associations'

      node_attribs = []

      if @options.brief || current_class.abstract_class?
        node_type = 'model-brief'
      else
        node_type = 'model'

        #
        #
        # Get Model Properties
        node_attribs = get_properties(model_klass)
        
      end
      @graph.add_node [node_type, current_class.name, node_attribs]

      generated = true


      # Process class associations
      #
      # get datamapper assoc
      associations = current_class.reflect_on_all_associations


      if @options.inheritance && ! @options.transitive

        # check if model inherit
        superclass_associations = current_class.superclass.reflect_on_all_associations

        associations = associations.select{|a| ! superclass_associations.include? a}
        # This doesn't works!
        # associations -= current_class.superclass.reflect_on_all_associations
      end


      associations.each do |a|
        process_association current_class.name, a 
      
      end





    elsif @options.all && (current_class.is_a? Class)
      # Not ActiveRecord::Base model
      node_type = @options.brief ? 'class-brief' : 'class'

      @graph.add_node [node_type, current_class.name]

      generated = true
    elsif @options.modules && (current_class.is_a? Module)
      @graph.add_node ['module', current_class.name]
    end

    # Only consider meaningful inheritance relations for generated classes
    if @options.inheritance && generated &&
        (current_class.superclass != ActiveRecord::Base) &&
        (current_class.superclass != Object)
      @graph.add_edge ['is-a', current_class.superclass.name, current_class.name]
    end

  end # process_class

  # Process a model association
  def process_association(class_name, assoc)

    STDERR.print "\t\tProcessing model association #{assoc.name.to_s}\n" if @options.verbose

    # Skip "belongs_to" associations
    return if assoc.macro.to_s == 'belongs_to' && !@options.show_belongs_to

    # Only non standard association names needs a label

    # from patch #12384
    # if assoc.class_name == assoc.name.to_s.singularize.camelize
    assoc_class_name = (assoc.class_name.respond_to? 'underscore') ? assoc.class_name.underscore.singularize.camelize : assoc.class_name
    if assoc_class_name == assoc.name.to_s.singularize.camelize
      assoc_name = ''
    else
      assoc_name = assoc.name.to_s
    end

    if ['has_one', 'belongs_to'].include? assoc.macro.to_s
      assoc_type = 'one-one'
    elsif assoc.macro.to_s == 'has_many' && (! assoc.options[:through])
      assoc_type = 'one-many'
    else # habtm or has_many, :through
      return if @habtm.include? [assoc.class_name, class_name, assoc_name]
      assoc_type = 'many-many'
      @habtm << [class_name, assoc.class_name, assoc_name]
    end
    # from patch #12384
    # @graph.add_edge [assoc_type, class_name, assoc.class_name, assoc_name]
    @graph.add_edge [assoc_type, class_name, assoc_class_name, assoc_name]
  end # process_association

end # class ModelsDiagram
