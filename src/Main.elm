port module Main exposing (..)

import Browser
import Html exposing (Html, button, div, form, h1, input, label, text)
import Html.Attributes exposing (attribute, class, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)



---- MODEL ----


type Action
    = Open
    | Supply
    | Remove


type alias OpenModalForm =
    { notionalAmount : Float
    , swapRate : Float
    , collateralCTokens : Float
    , isPayingFixed : Bool
    }


type alias SupplyModalForm =
    { supplyCTokenAmount : Float
    , supplyDollarAmount : Float
    , isPayingFixed : Bool
    }


type alias Model =
    { network : Maybe String
    , actionSelected : Action
    , isEnabled : Maybe Bool
    , openModal : OpenModalForm
    , supplyModal : Maybe SupplyModalForm
    }


init : ( Model, Cmd Msg )
init =
    ( { network = Nothing
      , actionSelected = Open
      , isEnabled = Nothing
      , openModal = { notionalAmount = 0, collateralCTokens = 0, swapRate = 4.5, isPayingFixed = True }
      , supplyModal = Nothing
      }
    , Cmd.none
    )



-- PORTS


port connect : String -> Cmd msg


port orderInfo : String -> Cmd msg


port networkReceiver : (String -> msg) -> Sub msg



---- UPDATE ----


type Msg
    = NoOp
    | Connect
    | SelectModal Action
    | Connected String
    | SelectPayingFixed Bool
    | InputNotional String
    | OrderInfo


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Connect ->
            ( model, connect "these txs" )

        Connected message ->
            let
                net =
                    if message == "unknown" then
                        "localhost"

                    else
                        message
            in
            ( { model | network = Just net }, Cmd.none )

        SelectModal action ->
            ( { model | actionSelected = action }, Cmd.none )

        SelectPayingFixed pf ->
            let
                oldOpenModal =
                    model.openModal
            in
            ( { model | openModal = { oldOpenModal | isPayingFixed = pf } }, Cmd.none )

        InputNotional notional ->
            let
                oldOpenModal =
                    model.openModal

                notionalFloat =
                    case String.toFloat notional of
                        Just a ->
                            a

                        _ ->
                            0
            in
            ( { model | openModal = { oldOpenModal | notionalAmount = notionalFloat } }, Cmd.none )

        OrderInfo ->
            ( model, orderInfo "str" )

        _ ->
            ( model, Cmd.none )



---- VIEW ----


view : Model -> Html Msg
view model =
    div [ id "container" ]
        [ header model.network
        , modal model
        , button [ onClick OrderInfo, class "connectButton" ] []
        ]


header : Maybe String -> Html Msg
header network =
    let
        connectButton =
            case network of
                Just name ->
                    div [ id "connectButton" ] [ text ("Connected to: " ++ name) ]

                Nothing ->
                    button [ onClick Connect, id "connectButton" ] [ text "Connected" ]
    in
    div [ id "header" ]
        [ h1 [ id "logo" ] [ text "Rho" ]
        , connectButton
        ]


modal : Model -> Html Msg
modal model =
    let
        action =
            model.actionSelected

        selectedModal =
            case action of
                Open ->
                    openModal model.openModal

                _ ->
                    div [] []
    in
    div [ id "modal" ]
        [ div [ id "buttonRow" ]
            [ selectorButton (action == Open) (SelectModal Open) "Open"
            , selectorButton (action == Supply) (SelectModal Supply) "Supply"
            , selectorButton (action == Remove) (SelectModal Remove) "Remove"
            ]
        , selectedModal
        ]


openModal : OpenModalForm -> Html Msg
openModal openModalForm =
    let
        cTokenText =
            if openModalForm.isPayingFixed then
                "Receive"

            else
                "Pay"
    in
    div [ class "form-elem" ]
        [ inputForm "Notional Amount (# DAI)" 0 openModalForm.notionalAmount InputNotional
        , textArea ("Collateral Required: " ++ String.fromFloat openModalForm.collateralCTokens ++ " CTokens, $" ++ "0")
        , div [ class "modal-field" ]
            [ selectorButton openModalForm.isPayingFixed
                (SelectPayingFixed True)
                "Pay"
            , selectorButton
                (not openModalForm.isPayingFixed)
                (SelectPayingFixed False)
                "Receive"
            , text (String.fromFloat openModalForm.swapRate ++ "%, " ++ cTokenText ++ " cDAI borrow rate")
            ]
        ]


textArea : String -> Html msg
textArea str =
    div [ class "modal-field" ] [ text str ]


inputForm : String -> Float -> Float -> (String -> msg) -> Html msg
inputForm name p v toMsg =
    div [ class "modal-field" ]
        [ label []
            [ text name
            , input [ type_ "number", placeholder (String.fromFloat p), value (String.fromFloat v), onInput toMsg, attribute "autofocus" "autofocus" ] []
            ]
        ]


selectorButton : Bool -> Msg -> String -> Html Msg
selectorButton isSelected action label =
    let
        buttonClass =
            if isSelected then
                "selectedButton"

            else
                "unselectedButton"
    in
    button [ onClick action, class buttonClass, class "text-button" ] [ text label ]



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    networkReceiver Connected



---- PROGRAM ----


main : Program () Model Msg
main =
    Browser.element
        { view = view
        , init = \_ -> init
        , update = update
        , subscriptions = subscriptions
        }
