port module Main exposing (..)

import Html exposing (..)
import Html.Attributes exposing (class, autofocus, placeholder, classList, checked, href, rel, type_, value, for)
import Json.Decode as Decode
import Json.Encode
import Html.Events exposing (on, keyCode, onInput, onCheck, onClick)
import Json.Decode.Pipeline exposing (decode, required)


type alias Todo =
    { title : String
    , isCompleted : Bool
    , isEditing : Bool
    , identifier : Int
    }


type FilterState
    = Active
    | All
    | Completed


type alias Model =
    { todos : List Todo
    , todo : Todo
    , filter : FilterState
    , nextIdentifier : Int
    }


type Msg
    = Add
    | Complete Todo Bool
    | Filter FilterState
    | UpdateField String
    | Destroy Todo
    | ClearAll
    | SetModel Model
    | NoOp


newTodo : Todo
newTodo =
    { title = ""
    , isCompleted = False
    , isEditing = False
    , identifier = 0
    }


onEnter : Msg -> Attribute Msg
onEnter msg =
    let
        isEnter code =
            if code == 13 then
                Decode.succeed msg
            else
                Decode.fail "Not the right key"
    in
        on "keydown" (keyCode |> Decode.andThen isEnter)


initialModel : Model
initialModel =
    { todos =
        [ { title = "The first todo"
          , isCompleted = False
          , isEditing = False
          , identifier = 1
          }
        ]
    , todo = { newTodo | identifier = 2 }
    , filter = All
    , nextIdentifier = 3
    }


filteredTodos : Model -> List Todo
filteredTodos model =
    let
        matchesFilter =
            case model.filter of
                All ->
                    (\_ -> True)

                Active ->
                    (\todo -> todo.isCompleted == False)

                Completed ->
                    (\todo -> todo.isCompleted == True)
    in
        List.filter matchesFilter model.todos


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Add ->
            let
                newModel =
                    { model
                        | todo = { newTodo | identifier = model.nextIdentifier }
                        , todos = model.todo :: model.todos
                        , nextIdentifier = model.nextIdentifier + 1
                    }
            in
                ( newModel
                , sendToStorage newModel
                )

        Complete todo isChecked ->
            let
                updateTodo thisTodo =
                    if thisTodo.identifier == todo.identifier then
                        { todo | isCompleted = isChecked }
                    else
                        thisTodo

                newModel =
                    { model | todos = List.map updateTodo model.todos }
            in
                ( newModel
                , sendToStorage newModel
                )

        Filter filterState ->
            let
                newModel =
                    { model | filter = filterState }
            in
                ( newModel, sendToStorage newModel )

        UpdateField text ->
            let
                todo =
                    model.todo

                updatedTodo =
                    { todo | title = text }

                newModel =
                    { model | todo = updatedTodo }
            in
                ( newModel, sendToStorage newModel )

        Destroy todo ->
            let
                newModel =
                    { model | todos = List.filter (\thisTodo -> thisTodo.identifier /= todo.identifier) model.todos }
            in
                ( newModel
                , sendToStorage newModel
                )

        ClearAll ->
            let
                newModel =
                    { model | todos = List.filter (\thisTodo -> thisTodo.isCompleted == False) model.todos }
            in
                ( newModel
                , sendToStorage newModel
                )

        SetModel newModel ->
            ( newModel, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


todoView : Todo -> Html Msg
todoView todo =
    li [ classList [ ( "completed", todo.isCompleted ) ] ]
        [ div [ class "view" ]
            [ input
                [ class "toggle"
                , type_ "checkbox"
                , checked todo.isCompleted
                , onCheck (\isChecked -> Complete todo isChecked)
                ]
                []
            , label [] [ text todo.title ]
            , button [ class "destroy", onClick (Destroy todo) ] []
            ]
        ]


filterItemView : Model -> FilterState -> Html Msg
filterItemView model filterState =
    li []
        [ a
            [ classList [ ( "selected", (model.filter == filterState) ) ]
            , href "#"
            , onClick (Filter filterState)
            ]
            [ text (toString filterState) ]
        ]


view : Model -> Html Msg
view model =
    div []
        [ node "style" [ type_ "text/css" ] [ text styles ]
        , section [ class "todoapp" ]
            [ header [ class "header" ]
                [ h1 [] [ text "todos" ]
                , input
                    [ class "new-todo"
                    , placeholder "what needs to be done?"
                    , value model.todo.title
                    , autofocus True
                    , onEnter Add
                    , onInput UpdateField
                    ]
                    []
                ]
            , section [ class "main" ]
                [ input [ class "toggle-all", type_ "checkbox" ] []
                , label [ for "toggle-all" ] [ text "Mark all as complete" ]
                , ul [ class "todo-list" ]
                    (List.map todoView (filteredTodos model))
                ]
            , footer [ class "footer" ]
                [ span [ class "todo-count" ]
                    [ strong [] [ text (toString (List.length (List.filter (\todo -> todo.isCompleted == False) model.todos))) ]
                    , text " item left"
                    ]
                , ul [ class "filters" ]
                    [ filterItemView model All
                    , filterItemView model Active
                    , filterItemView model Completed
                    ]
                , button
                    [ class "clear-completed"
                    , onClick ClearAll
                    ]
                    [ text "Clear completed" ]
                ]
            ]
        ]


subscriptions : Model -> Sub Msg
subscriptions model =
    storageInput mapStorageInput


encodeJson : Model -> Json.Encode.Value
encodeJson model =
    Json.Encode.object
        [ ( "todos", Json.Encode.list (List.map encodeTodo model.todos) )
        , ( "todo", encodeTodo model.todo )
        , ( "filter", encodeFilterState model.filter )
        , ( "nextIdentifier", Json.Encode.int model.nextIdentifier )
        ]


encodeTodo : Todo -> Json.Encode.Value
encodeTodo todo =
    Json.Encode.object
        [ ( "title", Json.Encode.string todo.title )
        , ( "isCompleted", Json.Encode.bool todo.isCompleted )
        , ( "isEditing", Json.Encode.bool todo.isEditing )
        , ( "identifier", Json.Encode.int todo.identifier )
        ]


encodeFilterState : FilterState -> Json.Encode.Value
encodeFilterState filterState =
    Json.Encode.string (toString filterState)


sendToStorage : Model -> Cmd Msg
sendToStorage model =
    encodeJson model |> storage


port storage : Json.Encode.Value -> Cmd msg


mapStorageInput : Decode.Value -> Msg
mapStorageInput modelJson =
    case (decodeModel modelJson) of
        Ok model ->
            SetModel model

        Err errorMessage ->
            let
                _ =
                    Debug.log "Error in mapStorageInput:" errorMessage
            in
                NoOp


decodeModel : Decode.Value -> Result String Model
decodeModel modelJson =
    Decode.decodeValue modelDecoder modelJson


modelDecoder : Decode.Decoder Model
modelDecoder =
    decode Model
        |> required "todos" (Decode.list todoDecoder)
        |> required "todo" todoDecoder
        |> required "filter" (Decode.string |> Decode.map filterStateDecoder)
        |> required "nextIdentifier" Decode.int


todoDecoder : Decode.Decoder Todo
todoDecoder =
    decode Todo
        |> required "title" Decode.string
        |> required "isCompleted" Decode.bool
        |> required "isEditing" Decode.bool
        |> required "identifier" Decode.int


filterStateDecoder : String -> FilterState
filterStateDecoder filter =
    case filter of
        "All" ->
            All

        "Active" ->
            Active

        "Completed" ->
            Completed

        _ ->
            let
                _ =
                    Debug.log "filterStateDecoder" <|
                        "Couldn't decode value "
                            ++ filter
                            ++ " so defaulting to All."
            in
                All


port storageInput : (Decode.Value -> msg) -> Sub msg


main : Program Never Model Msg
main =
    Html.program
        { init = ( initialModel, Cmd.none )
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


styles : String
styles =
    """
    html,
    body {
    margin: 0;
    padding: 0;
    }

    button {
    margin: 0;
    padding: 0;
    border: 0;
    background: none;
    font-size: 100%;
    vertical-align: baseline;
    font-family: inherit;
    font-weight: inherit;
    color: inherit;
    -webkit-appearance: none;
    appearance: none;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    }

    body {
    font: 14px 'Helvetica Neue', Helvetica, Arial, sans-serif;
    line-height: 1.4em;
    background: #f5f5f5;
    color: #4d4d4d;
    min-width: 230px;
    max-width: 550px;
    margin: 0 auto;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    font-weight: 300;
    }

    :focus {
    outline: 0;
    }

    .hidden {
    display: none;
    }

    .todoapp {
    background: #fff;
    margin: 130px 0 40px 0;
    position: relative;
    box-shadow: 0 2px 4px 0 rgba(0, 0, 0, 0.2),
                0 25px 50px 0 rgba(0, 0, 0, 0.1);
    }

    .todoapp input::-webkit-input-placeholder {
    font-style: italic;
    font-weight: 300;
    color: #e6e6e6;
    }

    .todoapp input::-moz-placeholder {
    font-style: italic;
    font-weight: 300;
    color: #e6e6e6;
    }

    .todoapp input::input-placeholder {
    font-style: italic;
    font-weight: 300;
    color: #e6e6e6;
    }

    .todoapp h1 {
    position: absolute;
    top: -155px;
    width: 100%;
    font-size: 100px;
    font-weight: 100;
    text-align: center;
    color: rgba(175, 47, 47, 0.15);
    -webkit-text-rendering: optimizeLegibility;
    -moz-text-rendering: optimizeLegibility;
    text-rendering: optimizeLegibility;
    }

    .new-todo,
    .edit {
    position: relative;
    margin: 0;
    width: 100%;
    font-size: 24px;
    font-family: inherit;
    font-weight: inherit;
    line-height: 1.4em;
    border: 0;
    color: inherit;
    padding: 6px;
    border: 1px solid #999;
    box-shadow: inset 0 -1px 5px 0 rgba(0, 0, 0, 0.2);
    box-sizing: border-box;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    }

    .new-todo {
    padding: 16px 16px 16px 60px;
    border: none;
    background: rgba(0, 0, 0, 0.003);
    box-shadow: inset 0 -2px 1px rgba(0,0,0,0.03);
    }

    .main {
    position: relative;
    z-index: 2;
    border-top: 1px solid #e6e6e6;
    }

    label[for='toggle-all'] {
    display: none;
    }

    .toggle-all {
    position: absolute;
    top: -55px;
    left: -12px;
    width: 60px;
    height: 34px;
    text-align: center;
    border: none; /* Mobile Safari */
    }

    .toggle-all:before {
    content: '>';
    font-size: 22px;
    color: #e6e6e6;
    padding: 10px 27px 10px 27px;
    }

    .toggle-all:checked:before {
    color: #737373;
    }

    .todo-list {
    margin: 0;
    padding: 0;
    list-style: none;
    }

    .todo-list li {
    position: relative;
    font-size: 24px;
    border-bottom: 1px solid #ededed;
    }

    .todo-list li:last-child {
    border-bottom: none;
    }

    .todo-list li.editing {
    border-bottom: none;
    padding: 0;
    }

    .todo-list li.editing .edit {
    display: block;
    width: 506px;
    padding: 12px 16px;
    margin: 0 0 0 43px;
    }

    .todo-list li.editing .view {
    display: none;
    }

    .todo-list li .toggle {
    text-align: center;
    width: 40px;
    /* auto, since non-WebKit browsers doesn't support input styling */
    height: auto;
    position: absolute;
    top: 0;
    bottom: 0;
    margin: auto 0;
    border: none; /* Mobile Safari */
    -webkit-appearance: none;
    appearance: none;
    }

    .todo-list li .toggle:after {
    content: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="-10 -18 100 135"><circle cx="50" cy="50" r="50" fill="none" stroke="#ededed" stroke-width="3"/></svg>');
    }

    .todo-list li .toggle:checked:after {
    content: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="-10 -18 100 135"><circle cx="50" cy="50" r="50" fill="none" stroke="#bddad5" stroke-width="3"/><path fill="#5dc2af" d="M72 25L42 71 27 56l-4 4 20 20 34-52z"/></svg>');
    }

    .todo-list li label {
    word-break: break-all;
    padding: 15px 60px 15px 15px;
    margin-left: 45px;
    display: block;
    line-height: 1.2;
    transition: color 0.4s;
    }

    .todo-list li.completed label {
    color: #d9d9d9;
    text-decoration: line-through;
    }

    .todo-list li .destroy {
    display: none;
    position: absolute;
    top: 0;
    right: 10px;
    bottom: 0;
    width: 40px;
    height: 40px;
    margin: auto 0;
    font-size: 30px;
    color: #cc9a9a;
    margin-bottom: 11px;
    transition: color 0.2s ease-out;
    }

    .todo-list li .destroy:hover {
    color: #af5b5e;
    }

    .todo-list li .destroy:after {
    content: 'x';
    }

    .todo-list li:hover .destroy {
    display: block;
    }

    .todo-list li .edit {
    display: none;
    }

    .todo-list li.editing:last-child {
    margin-bottom: -1px;
    }

    .footer {
    color: #777;
    padding: 10px 15px;
    height: 20px;
    text-align: center;
    border-top: 1px solid #e6e6e6;
    }

    .footer:before {
    content: '';
    position: absolute;
    right: 0;
    bottom: 0;
    left: 0;
    height: 50px;
    overflow: hidden;
    box-shadow: 0 1px 1px rgba(0, 0, 0, 0.2),
                0 8px 0 -3px #f6f6f6,
                0 9px 1px -3px rgba(0, 0, 0, 0.2),
                0 16px 0 -6px #f6f6f6,
                0 17px 2px -6px rgba(0, 0, 0, 0.2);
    }

    .todo-count {
    float: left;
    text-align: left;
    }

    .todo-count strong {
    font-weight: 300;
    }

    .filters {
    margin: 0;
    padding: 0;
    list-style: none;
    position: absolute;
    right: 0;
    left: 0;
    }

    .filters li {
    display: inline;
    }

    .filters li a {
    color: inherit;
    margin: 3px;
    padding: 3px 7px;
    text-decoration: none;
    border: 1px solid transparent;
    border-radius: 3px;
    }

    .filters li a:hover {
    border-color: rgba(175, 47, 47, 0.1);
    }

    .filters li a.selected {
    border-color: rgba(175, 47, 47, 0.2);
    }

    .clear-completed,
    html .clear-completed:active {
    float: right;
    position: relative;
    line-height: 20px;
    text-decoration: none;
    cursor: pointer;
    }

    .clear-completed:hover {
    text-decoration: underline;
    }

    .info {
    margin: 65px auto 0;
    color: #bfbfbf;
    font-size: 10px;
    text-shadow: 0 1px 0 rgba(255, 255, 255, 0.5);
    text-align: center;
    }

    .info p {
    line-height: 1;
    }

    .info a {
    color: inherit;
    text-decoration: none;
    font-weight: 400;
    }

    .info a:hover {
    text-decoration: underline;
    }

    /*
    Hack to remove background from Mobile Safari.
    Can't use it globally since it destroys checkboxes in Firefox
    */
    @media screen and (-webkit-min-device-pixel-ratio:0) {
    .toggle-all,
    .todo-list li .toggle {
        background: none;
    }

    .todo-list li .toggle {
        height: 40px;
    }

    .toggle-all {
        -webkit-transform: rotate(90deg);
        transform: rotate(90deg);
        -webkit-appearance: none;
        appearance: none;
    }
    }

    @media (max-width: 430px) {
    .footer {
        height: 50px;
    }

    .filters {
        bottom: 10px;
    }
    }
    """
