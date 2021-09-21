module Mocktail
  class ReplacesType
    def initialize
      @top_shelf = TopShelf.instance
      @handles_dry_call = HandlesDryCall.new

      @registers_stubbing = RegistersStubbing.new
      @imitates_type = ImitatesType.new
      @validates_arguments = ValidatesArguments.new
      @logs_call = LogsCall.new
      @fulfills_stubbing = FulfillsStubbing.new
    end

    def replace(type)
      @top_shelf.register_type_replacement_for_current_thread!(type)

      if !@top_shelf.already_replaced?(type)
        original_methods = (
          [(:new if type.is_a?(Class))] + type.singleton_methods
        ).compact.map { |name| [name, type.method(name)] }.to_h

        handles_dry_call = @handles_dry_call
        validates_arguments = @validates_arguments
        imitates_type = @imitates_type
        logs_call = @logs_call
        fulfills_stubbing = @fulfills_stubbing

        if type.is_a?(Class)
          type.singleton_class.send(:undef_method, :new)
          new_new_method = type.define_singleton_method :new, ->(*args, **kwargs, &block) {
            if TopShelf.instance.replaced_on_current_thread?(type)
              new_call = Call.new(
                singleton: true,
                double: type,
                original_type: type,
                dry_type: type,
                method: :new,
                original_method: original_methods[:new],
                args: args,
                kwargs: kwargs,
                block: block
              )
              initialize_call = Call.new(
                original_method: type.instance_method(:initialize),
                args: args,
                kwargs: kwargs
              )
              validates_arguments.validate(initialize_call)
              logs_call.log(new_call)
              if fulfills_stubbing.satisfaction(new_call)
                fulfills_stubbing.fulfill(new_call)
              else
                imitates_type.imitate(type)
              end
            else
              original_methods[:new].call(*args, **kwargs, &block)
            end
          }
        end

        replacement_methods = original_methods.map { |name, original_method|
          next if type.is_a?(Class) && name == :new

          type.singleton_class.send(:undef_method, name)
          type.define_singleton_method name, ->(*args, **kwargs, &block) {
            if TopShelf.instance.replaced_on_current_thread?(type)
              handles_dry_call.handle(Call.new(
                singleton: true,
                double: type,
                original_type: type,
                dry_type: type,
                method: name,
                original_method: original_method,
                args: args,
                kwargs: kwargs,
                block: block
              ))
            else
              original_method.call(*args, **kwargs, &block)
            end
          }
        }

        @top_shelf.store_type_replacement(TypeReplacement.new(
          type: type,
          original_methods: original_methods,
          replacement_methods: [new_new_method] + replacement_methods
        ))
      end
    end
  end
end
