defmodule ElixirScript.Translator do
  require Logger
  alias ElixirScript.Translator.Primative
  alias ElixirScript.Translator.PatternMatching
  alias ElixirScript.Translator.Data
  alias ElixirScript.Translator.Function
  alias ElixirScript.Translator.Expression
  alias ElixirScript.Translator.Import
  alias ElixirScript.Translator.Control
  alias ElixirScript.Translator.Module
  alias ElixirScript.Translator.Kernel, as: ExKernel

  @doc """
  Translates Elixir AST to JavaScript AST
  """
  def translate(ast) do
    do_translate(ast)
  end

  def do_translate(ast) when is_number(ast) or is_binary(ast) or is_boolean(ast) or is_nil(ast) do
    Primative.make_literal(ast)
  end

  def do_translate(ast) when is_atom(ast) do
    Primative.make_atom(ast)
  end

  def do_translate(ast) when is_list(ast) do
    Primative.make_array(ast)
  end

  def do_translate({ one, two }) do
    Primative.make_tuple({one, two})
  end

  def do_translate({:%, _, [alias_info, data]}) do
    {_, _, name} = alias_info
    {_, _, data} = data
    Data.make_struct(name, data)
  end

  def do_translate({:%{}, _, [{:|, _, [map, data]}]}) do
    Data.make_map_update(map, data);
  end

  def do_translate({:%{}, _, properties}) do
    Data.make_object(properties)
  end

  def do_translate({:<<>>, _, elements}) do
    is_interpolated_string = Enum.any?(elements, fn(x) -> 
      case x do
        {:::, _, _} ->
          true
        _ ->
          false
      end
    end)

    case is_interpolated_string do
      true ->
        Primative.make_interpolated_string(elements)
      _ ->
        Primative.make_array(elements)
    end
  end

  def do_translate({:., _, [module_name, function_name]}) do
    Function.make_function_or_property_call(module_name, function_name)
  end

  def do_translate({{:., _, [module_name, function_name]}, _, [] }) do
    Function.make_function_or_property_call(module_name, function_name)
  end

  def do_translate({{:., _, [module_name, function_name]}, _, params }) do
    Function.make_function_call(module_name, function_name, params)
  end

  def do_translate({:__aliases__, _, aliases}) do
    Primative.make_identifier(aliases)
  end

  def do_translate({:__block__, _, expressions }) do
    Control.make_block(expressions)
  end

  def do_translate({:import, _, [{:__aliases__, _, module_name_list}]}) do
    Import.make_import(module_name_list)
  end

  def do_translate({:import, _, [{:__aliases__, _, module_name_list}, [only: function_list] ]}) do
    Import.make_import(module_name_list, function_list)
  end

  def do_translate({:alias, _, alias_info}) do
    Import.make_alias_import(alias_info)
  end

  def do_translate({:require, _, [{:__aliases__, _, module_name_list}]}) do
    Import.make_default_import(module_name_list)
  end

  def do_translate({:case, _, [condition, [do: clauses]]}) do
    Control.make_case(condition, clauses)
  end

  def do_translate({:cond, _, [[do: clauses]]}) do
    Control.make_cond(clauses)
  end

  def do_translate({:for, _, generators}) do
    Control.make_for(generators)
  end

  def do_translate({:fn, _, [{:->, _, [params, body]}]}) do
    Function.make_anonymous_function(params, body)
  end

  def do_translate({:.., _, [first, last]}) do
    ExKernel.make_range(first, last)
  end

  def do_translate({:{}, _, elements}) do
    Primative.make_tuple(elements)
  end

  def do_translate({:-, _, [number]}) when is_number(number) do
    Expression.make_negative_number(number)
  end

  def do_translate({:=, _, [left, right]}) do
    PatternMatching.bind(left, right)
  end

  def do_translate({:<>, _, [left, right]}) do
    Expression.make_binary_expression(:+, left, right)
  end

  def do_translate({operator, _, [left, right]}) when operator in [:+, :-, :/, :*, :==, :!=] do
    Expression.make_binary_expression(operator, left, right)
  end

  def do_translate({:def, _, [{:when, _, [{name, _, params} | guards] }, [do: body]] }) do
    Function.make_export_function(name, params, body, guards)
  end

  def do_translate({:def, _, [{name, _, params}, [do: body]]}) do
    Function.make_export_function(name, params, body)
  end

  def do_translate({:defp, _, [{:when, _, [{name, _, params} | guards] }, [do: body]] }) do
    Function.make_function(name, params, body, guards)
  end

  def do_translate({:defp, _, [{name, _, params}, [do: body]]}) do
    Function.make_function(name, params, body)
  end

  def do_translate({:defstruct, _, attributes}) do
    Data.make_defstruct(attributes)
  end

  def do_translate({:defexception, _, attributes}) do
    Data.make_defexception(attributes)
  end

  def do_translate({:raise, _, [alias_info, attributes]}) do
    {_, _, name} = alias_info

    Data.throw_error(name, attributes)
  end

  def do_translate({:raise, _, [message]}) do
    Data.throw_error(message)
  end

  def do_translate({:if, _, [test, blocks]}) do
    Control.make_if(test, blocks)
  end

  def do_translate({:defmodule, _, [{:__aliases__, _, module_name_list}, [do: body]]}) do
    Module.make_module(module_name_list, body)
  end

  def do_translate({:@, _, [{name, [], [value]}]}) do
    Module.make_attribute(name, value)
  end

  def do_translate({:|>, _, [left, right]}) do
    case right do
      {{:., meta, [module, fun]}, meta2, params} ->
        translate({{:., meta, [module, fun]}, meta2, [left] ++ params})  
      {fun, meta, params} ->
        translate({fun, meta, [left] ++ params})     
    end
  end

  def do_translate({name, metadata, params}) when is_list(params) do
    case metadata[:import] do
      Kernel ->
        name = case name do
          :in ->
            :_in
          _ ->
            name
        end

        Function.make_function_call(:Kernel, name, params)
      _ ->
        Function.make_function_call(name, params)        
    end
  end

  def do_translate({name, _, _}) do
    Primative.make_identifier(name)
  end

end