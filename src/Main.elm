port module Main exposing (..)

import Browser
import Decimal exposing (Decimal)
import Html exposing (Html, button, div, form, h1, h3, input, label, text)
import Html.Attributes exposing (attribute, class, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Time



---- MODEL ----


type Action
    = Open
    | Supply
    | Remove


type alias Model =
    { underlying : String
    , invalidNetworkBanner : Bool
    , selectedAddr : String
    , network : Maybe String
    , actionSelected : Action

    --open modal form
    , notionalAmount : Decimal
    , collateralCTokens : Decimal
    , collateralDollars : Decimal
    , swapRate : Decimal
    , isPayingFixed : Bool

    --supply modal form
    , supplyCTokenAmount : Decimal
    , supplyDollarAmount : Decimal
    , isApproved : Bool
    }


type alias ConnectResponse =
    { network : String, selectedAddr : String }


init : ( Model, Cmd Msg )
init =
    ( { underlying = "DAI"
      , invalidNetworkBanner = False
      , selectedAddr = ""
      , network = Nothing
      , actionSelected = Open
      , notionalAmount = Decimal.zero
      , collateralCTokens = Decimal.zero
      , collateralDollars = Decimal.zero
      , swapRate = Decimal.zero
      , isPayingFixed = True
      , supplyCTokenAmount = Decimal.zero
      , supplyDollarAmount = Decimal.zero
      , isApproved = True
      }
    , isApprovedCall ()
    )



-- PORTS


port connect : () -> Cmd msg


port isApprovedCall : () -> Cmd msg


port approveSend : () -> Cmd msg


port supplyCTokensSend : String -> Cmd msg


port supplyToCTokensCall : String -> Cmd msg


port orderInfo : ( Bool, String ) -> Cmd msg


port openSwapSend : ( Bool, String ) -> Cmd msg


port connectReceiver : (ConnectResponse -> msg) -> Sub msg


port enableReceiver : (Bool -> msg) -> Sub msg


port supplyToCTokensReceiver : (String -> msg) -> Sub msg


port orderInfoReceiver : (( String, String, String ) -> msg) -> Sub msg



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ connectReceiver Connected
        , enableReceiver Approve
        , supplyToCTokensReceiver SupplyCTokens
        , orderInfoReceiver OrderInfo
        , Time.every 5000 Tick
        ]



---- UPDATE ----


type Msg
    = NoOp
    | SelectModal Action
    | SelectPayingFixed Bool
    | NotionalAmountInput String
    | OrderInfo ( String, String, String )
    | Approve Bool
    | ApproveCmd
    | Connected ConnectResponse
    | ConnectCmd
    | SupplyAmountInput String
    | SupplyCTokens String
    | SupplyTx
    | Tick Time.Posix


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ConnectCmd ->
            ( model, connect () )

        Connected resp ->
            ( { model | network = Just resp.network, selectedAddr = resp.selectedAddr }, Cmd.none )

        SelectModal action ->
            ( { model | actionSelected = action }, Cmd.none )

        SelectPayingFixed pf ->
            let
                notionalStr =
                    Decimal.toString model.notionalAmount
            in
            ( { model | isPayingFixed = pf }, orderInfo ( pf, notionalStr ) )

        ApproveCmd ->
            ( model, approveSend () )

        Approve isApproved ->
            ( { model | isApproved = isApproved }, Cmd.none )

        SupplyAmountInput amt ->
            let
                ( decAmt, strAmt ) =
                    formatInput amt
            in
            ( { model | supplyDollarAmount = decAmt }, supplyToCTokensCall strAmt )

        SupplyCTokens ctokens ->
            ( { model | supplyCTokenAmount = toDec ctokens model.supplyCTokenAmount }, Cmd.none )

        SupplyTx ->
            ( model, supplyCTokensSend (Decimal.toString model.supplyCTokenAmount) )

        NotionalAmountInput notional ->
            let
                ( decAmt, strAmt ) =
                    formatInput notional
            in
            ( { model | notionalAmount = decAmt }, orderInfo ( model.isPayingFixed, strAmt ) )

        OrderInfo ( swapRate, collatCToken, collatDollars ) ->
            let
                percRate =
                    100 |> Decimal.fromInt |> Decimal.mul (toDec swapRate model.swapRate)

                collatCTokenDec =
                    toDec collatCToken model.collateralCTokens

                collatDollarDec =
                    toDec collatDollars model.collateralDollars
            in
            ( { model | collateralCTokens = collatCTokenDec, swapRate = percRate, collateralDollars = collatDollarDec }, Cmd.none )

        OpenTx ->
            ( model, openSwapSend ( model.isPayingFixed, model.notionalAmount ) )

        Tick _ ->
            ( model, isApprovedCall () )

        _ ->
            ( model, Cmd.none )



---- VIEW ----


view : Model -> Html Msg
view model =
    div [ id "container" ]
        [ header model.network model.selectedAddr
        , modal model
        ]


header : Maybe String -> String -> Html Msg
header network selectedAddr =
    let
        ctaButton =
            case network of
                Just name ->
                    div [ id "connectButton" ] [ text ("🔗: " ++ name ++ " " ++ String.slice 0 7 selectedAddr ++ "...") ]

                Nothing ->
                    button [ onClick ConnectCmd, class "ctaButton", id "connectButton" ] [ text "Connect Metamask" ]
    in
    div [ id "header" ]
        [ h1 [ id "logo" ] [ text "Rho" ]
        , h3 [ id "title" ] [ text "cDAI Interest Rate Swaps" ]
        , ctaButton
        ]


modal : Model -> Html Msg
modal model =
    let
        action =
            model.actionSelected

        selectedModal =
            case action of
                Open ->
                    openModal model

                Supply ->
                    supplyModal model

                _ ->
                    div [] []

        maybeEnableButton =
            case model.isApproved of
                True ->
                    div [] []

                False ->
                    button [ onClick ApproveCmd ] [ text ("Enable c" ++ model.underlying) ]
    in
    div [ id "modal" ]
        [ div [ id "buttonRow" ]
            [ selectorButton (action == Open) (SelectModal Open) "Open"
            , selectorButton (action == Supply) (SelectModal Supply) "Supply"
            , selectorButton (action == Remove) (SelectModal Remove) "Remove"
            ]
        , maybeEnableButton
        , selectedModal
        ]


supplyModal : Model -> Html Msg
supplyModal model =
    div [ class "form-elem" ]
        [ inputForm "$ of cDAI to supply: " "0" (Decimal.toString model.supplyDollarAmount) SupplyAmountInput
        , textArea ("cTokens: " ++ Decimal.toString model.supplyCTokenAmount)
        , button [ onClick SupplyTx, class "ctaButton" ] [ text "Supply Liquidity" ]
        ]


openModal : Model -> Html Msg
openModal model =
    let
        cTokenText =
            if model.isPayingFixed then
                "Receive"

            else
                "Pay"

        swapRateText =
            case Decimal.toString model.swapRate of
                "0" ->
                    "XX%"

                a ->
                    a ++ "%"
    in
    div [ class "form-elem" ]
        [ inputForm "Notional Amount (# DAI)         " "0" (Decimal.toString model.notionalAmount) NotionalAmountInput
        , textArea ("Collateral Required ($)       : " ++ Decimal.toString model.collateralDollars)
        , textArea ("Collateral Required (CTokens) : " ++ Decimal.toString model.collateralCTokens)
        , div [ class "modal-field" ]
            [ selectorButton model.isPayingFixed
                (SelectPayingFixed True)
                "Pay"
            , selectorButton
                (not model.isPayingFixed)
                (SelectPayingFixed False)
                "Receive"
            , text swapRateText
            ]
        , div [ class "modal-field" ] [ text (cTokenText ++ " the cDAI borrow rate") ]
        , button [ onClick OpenTx, class "ctaButton" ] [ text "Open Swap" ]
        ]


textArea : String -> Html msg
textArea str =
    div [ class "modal-field" ] [ text str ]


inputForm : String -> String -> String -> (String -> msg) -> Html msg
inputForm name placeholderVal val toMsg =
    div [ class "modal-field" ]
        [ label []
            [ text name
            , input [ type_ "number", attribute "placeholder" placeholderVal, value val, onInput toMsg, attribute "autofocus" "autofocus" ] []
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


toDec : String -> Decimal -> Decimal
toDec newStr default =
    case ( newStr, Decimal.fromString newStr ) of
        ( "", _ ) ->
            Decimal.zero

        ( n, Nothing ) ->
            default

        ( n, Just newDec ) ->
            newDec


formatInput : String -> ( Decimal, String )
formatInput str =
    case Decimal.fromString str of
        Nothing ->
            ( Decimal.zero, "0" )

        Just n ->
            ( n, Decimal.toString n )



---- PROGRAM ----


main : Program () Model Msg
main =
    Browser.element
        { view = view
        , init = \_ -> init
        , update = update
        , subscriptions = subscriptions
        }
