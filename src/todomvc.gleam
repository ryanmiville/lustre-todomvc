import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/order
import lustre
import lustre/attribute.{type Attribute}
import lustre/effect.{type Effect}
import lustre/element
import lustre/element/html
import lustre/event

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL ----------------------------------------------------------------------

type Model {
  Model(
    todos: Dict(Int, Todo),
    filter: Filter,
    last_id: Int,
    new_todo_input: String,
    existing_todo_input: String,
  )
}

type Todo {
  Todo(id: Int, description: String, completed: Bool, editing: Bool)
}

fn compare(a: Todo, b: Todo) -> order.Order {
  int.compare(a.id, b.id)
}

type Filter {
  All
  Active
  Completed
}

fn init(_) -> #(Model, Effect(msg)) {
  #(Model(dict.new(), All, 0, "", ""), effect.none())
}

// UPDATE ---------------------------------------------------------------------

type Msg {
  Noop
  UserAddedTodo
  UserBlurredExistingTodo(id: Int)
  UserClickedClearCompleted
  UserClickedFilter(Filter)
  UserClickedToggle(id: Int, checked: Bool)
  UserClickedToggleAll(checked: Bool)
  UserDeletedTodo(id: Int)
  UserDoubleClickedTodo(id: Int, input: String)
  UserEditedTodo(id: Int)
  UserUpdatedExistingInput(value: String)
  UserUpdatedNewInput(value: String)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let Model(todos, _, last_id, new_todo_input, existing_todo_input) = model

  case msg {
    Noop -> #(model, effect.none())

    UserAddedTodo -> {
      let description = new_todo_input
      let last_id = last_id + 1
      let new = Todo(last_id, description, False, False)
      let todos = dict.insert(todos, last_id, new)
      let model = Model(..model, todos:, last_id:, new_todo_input: "")
      #(model, effect.none())
    }

    UserBlurredExistingTodo(id) -> {
      let todos =
        dict.upsert(todos, id, fn(i) {
          let assert Some(i) = i
          Todo(..i, editing: False)
        })
      let model = Model(..model, todos:, existing_todo_input: "")
      #(model, effect.none())
    }

    UserClickedClearCompleted -> {
      let todos = dict.filter(todos, fn(_, item) { !item.completed })
      #(Model(..model, todos:), effect.none())
    }

    UserClickedFilter(filter) -> {
      #(Model(..model, filter:), effect.none())
    }

    UserClickedToggle(id, checked) -> {
      let todos =
        dict.upsert(todos, id, fn(i) {
          let assert Some(i) = i
          Todo(..i, completed: checked)
        })
      let model = Model(..model, todos:)
      #(model, effect.none())
    }

    UserClickedToggleAll(checked) -> {
      let todos =
        dict.map_values(todos, fn(_, i) { Todo(..i, completed: checked) })
      let model = Model(..model, todos:)
      #(model, effect.none())
    }

    UserDeletedTodo(id) -> {
      let todos = dict.delete(todos, id)
      let model = Model(..model, todos:)
      #(model, effect.none())
    }

    UserDoubleClickedTodo(id, input) -> {
      let todos =
        dict.upsert(todos, id, fn(i) {
          let assert Some(i) = i
          Todo(..i, editing: True)
        })

      let model = Model(..model, todos:, existing_todo_input: input)
      #(model, focus_edit_input())
    }

    UserEditedTodo(id) -> {
      use <- bool.guard(existing_todo_input == "", #(model, delete_todo(id)))

      let description = existing_todo_input
      let todos =
        dict.upsert(todos, id, fn(i) {
          let assert Some(i) = i
          Todo(..i, description:, editing: False)
        })
      let model = Model(..model, todos:)
      #(model, effect.none())
    }

    UserUpdatedExistingInput(existing_todo_input) -> {
      let model = Model(..model, existing_todo_input:)
      #(model, effect.none())
    }

    UserUpdatedNewInput(new_todo_input) -> {
      #(Model(..model, new_todo_input:), effect.none())
    }
  }
}

// VIEW -----------------------------------------------------------------------

fn view(model: Model) {
  html.div([], [
    html.div([attribute.class("todoapp")], [
      header(model),
      main_content(model),
      footer(model),
    ]),
    edit_message(),
  ])
}

fn header(model: Model) {
  html.header([attribute.class("header")], [
    html.h1([], [html.text("todos")]),
    new_todo(model),
  ])
}

fn main_content(model: Model) {
  let visible_todos = case model.filter {
    All ->
      dict.values(model.todos)
      |> list.sort(compare)
    Active ->
      dict.values(model.todos)
      |> list.filter(fn(i) { !i.completed })
      |> list.sort(compare)
    Completed ->
      dict.values(model.todos)
      |> list.filter(fn(i) { i.completed })
      |> list.sort(compare)
  }

  html.main([attribute.class("main")], [
    toggle(dict.values(model.todos) |> list.sort(compare)),
    todo_list(visible_todos, model),
  ])
}

fn footer(model: Model) {
  let active_count =
    dict.values(model.todos)
    |> list.count(fn(i) { !i.completed })
  html.footer([attribute.class("footer")], [
    todo_count(active_count),
    filters(model.filter),
    clear_completed(model),
  ])
}

fn new_todo(model: Model) {
  html.div([attribute.class("view")], [
    input(
      on_enter: on_enter(UserAddedTodo),
      on_input: UserUpdatedNewInput,
      on_blur: Noop,
      placeholder: "What needs to be done?",
      autofocus: True,
      label: "New Todo Input",
      value: model.new_todo_input,
    ),
  ])
}

fn toggle(visible_todos: List(Todo)) {
  use <- bool.guard(list.is_empty(visible_todos), element.none())

  html.div([attribute.class("toggle-all-container")], [
    html.input([
      attribute.class("toggle-all"),
      attribute.type_("checkbox"),
      attribute.id("toggle-all"),
      event.on_check(UserClickedToggleAll),
    ]),
    html.label(
      [attribute.class("toggle-all-label"), attribute.for("toggle-all")],
      [html.text("Toggle All Input")],
    ),
  ])
}

fn todo_list(visible_todos: List(Todo), model: Model) {
  let items = list.map(visible_todos, todo_item(_, model))
  html.ul([attribute.class("todo-list")], items)
}

fn todo_item(item: Todo, model: Model) {
  let cn = case item.completed {
    True -> "completed"
    False -> ""
  }

  let el = case item.editing {
    True -> todo_item_edit(item, model)
    False -> todo_item_not_edit(item)
  }

  html.li([attribute.class(cn)], [el])
}

fn todo_item_edit(item: Todo, model: Model) {
  html.div([attribute.class("view")], [
    input(
      on_enter: on_enter(UserEditedTodo(item.id)),
      on_input: UserUpdatedExistingInput,
      on_blur: UserBlurredExistingTodo(item.id),
      placeholder: "",
      autofocus: False,
      label: "Edit Todo Input",
      value: model.existing_todo_input,
    ),
  ])
}

fn todo_item_not_edit(item: Todo) {
  html.div([attribute.class("view")], [
    html.input([
      attribute.class("toggle"),
      attribute.type_("checkbox"),
      attribute.checked(item.completed),
      event.on_check(UserClickedToggle(item.id, _)),
    ]),
    html.label(
      [on_double_click(UserDoubleClickedTodo(item.id, item.description))],
      [html.text(item.description)],
    ),
    html.button(
      [attribute.class("destroy"), event.on_click(UserDeletedTodo(item.id))],
      [],
    ),
  ])
}

fn todo_count(count: Int) {
  let text = case count {
    1 -> "1 item left!"
    n -> int.to_string(n) <> " items left!"
  }
  html.span([attribute.class("todo-count")], [html.text(text)])
}

fn filters(current: Filter) {
  [All, Active, Completed]
  |> list.map(filter_item(_, current))
  |> html.ul([attribute.class("filters")], _)
}

fn filter_item(item: Filter, current: Filter) {
  let cn = case item == current {
    True -> "selected"
    False -> ""
  }

  let text = case item {
    All -> "All"
    Active -> "Active"
    Completed -> "Completed"
  }
  html.li([], [
    html.a([attribute.class(cn), event.on_click(UserClickedFilter(item))], [
      html.text(text),
    ]),
  ])
}

fn clear_completed(model: Model) {
  let disabled = dict.is_empty(model.todos)
  html.button(
    [
      attribute.class("clear-completed"),
      attribute.disabled(disabled),
      event.on_click(UserClickedClearCompleted),
    ],
    [html.text("Clear Completed")],
  )
}

fn input(
  on_enter on_enter: Attribute(Msg),
  on_input on_input: fn(String) -> Msg,
  on_blur on_blur: Msg,
  placeholder placeholder: String,
  autofocus autofocus: Bool,
  label label: String,
  value value: String,
) {
  html.div([attribute.class("input-container")], [
    html.input([
      attribute.class("new-todo"),
      attribute.id("todo-input"),
      attribute.type_("text"),
      attribute.autofocus(autofocus),
      attribute.placeholder(placeholder),
      attribute.value(value),
      on_enter,
      event.on_input(on_input),
      event.on_blur(on_blur),
    ]),
    html.label(
      [attribute.class("visually-hidden"), attribute.for("todo-input")],
      [html.text(label)],
    ),
  ])
}

fn edit_message() {
  html.footer([attribute.class("info")], [
    html.p([], [html.text("Double-click to edit a todo")]),
  ])
}

fn delete_todo(id: Int) {
  use dispatch <- effect.from
  dispatch(UserDeletedTodo(id))
}

fn on_double_click(msg: Msg) {
  use _ <- event.on("dblclick")
  Ok(msg)
}

fn on_enter(msg: Msg) -> Attribute(Msg) {
  event.on_keydown(fn(key) {
    case key {
      "Enter" -> msg
      _ -> Noop
    }
  })
}

fn focus_edit_input() -> Effect(msg) {
  use _ <- effect.from
  use <- after_render
  focus(".todo-list .new-todo")
}

@external(javascript, "./todomvc_ffi.mjs", "focus")
fn focus(selector: String) -> Nil

@external(javascript, "./todomvc_ffi.mjs", "after_render")
fn after_render(do: fn() -> a) -> Nil
