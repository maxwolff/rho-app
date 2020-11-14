port module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Decimal exposing (Decimal)
import Html exposing (Html, a, button, div, form, h1, h3, h4, input, label, li, option, select, text, ul)
import Html.Attributes exposing (attribute, class, height, href, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Time
import Url
import Url.Parser


type Page
    = App
    | History
    | Landing


defaultPage : Page
defaultPage =
    Landing


routeParser : Url.Parser.Parser (Page -> a) a
routeParser =
    Url.Parser.oneOf
        [ Url.Parser.map App (Url.Parser.s "app")
        , Url.Parser.map History (Url.Parser.s "history")
        ]


getTitle : Page -> String
getTitle page =
    case page of
        App ->
            "Rho | App"

        History ->
            "Rho | History"

        Landing ->
            "Rho"


getPage : Url.Url -> ( Page, Cmd msg, String )
getPage location =
    let
        page =
            Url.Parser.parse routeParser location |> Maybe.withDefault defaultPage

        cmd =
            case page of
                History ->
                    Cmd.batch [ isConnected (), swapHistory () ]

                App ->
                    Cmd.batch [ isConnected (), isApprovedCall (), cTokenBalance (), supplyBalance () ]

                Landing ->
                    Cmd.none

        initTitle =
            getTitle page
    in
    ( page, cmd, initTitle )



---- MODEL ----


type Action
    = Open
    | Close
    | Supply
    | Remove


type alias Model =
    { -- page stuff
      key : Nav.Key
    , page : Page
    , title : String
    , underlying : String
    , collateral : String
    , duration : String

    -- metamask
    , connectionStatus : ConnectionStatus

    -- modal state
    , actionSelected : Action

    --open modal form
    , notionalAmount : Decimal
    , collateralCTokens : Decimal
    , collateralDollars : Decimal
    , swapRate : Decimal
    , isPayingFixed : Bool
    , supplyBalanceCToken : Decimal
    , cTokenBalance : Decimal

    --supply modal form
    , supplyCTokenAmount : Decimal
    , supplyDollarAmount : Decimal
    , isApproved : Bool

    -- history page
    , historicalSwaps : List HistoricalSwap
    }


type alias Web3Connection =
    { selectedAddr : String
    , network : String
    }


type ConnectionStatus
    = Connected Web3Connection
    | NotConnected
    | InvalidNetwork
    | NoMetamask


type alias Flags =
    { underlying : String
    , collateral : String
    , duration : String
    }


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        ( page, cmd, title ) =
            getPage url
    in
    ( { key = key
      , page = page
      , title = title
      , underlying = flags.underlying
      , collateral = flags.collateral
      , duration = flags.duration
      , connectionStatus = NotConnected
      , actionSelected = Open
      , notionalAmount = Decimal.zero
      , collateralCTokens = Decimal.zero
      , collateralDollars = Decimal.zero
      , swapRate = Decimal.zero
      , isPayingFixed = True
      , supplyBalanceCToken = Decimal.zero
      , cTokenBalance = Decimal.zero
      , supplyCTokenAmount = Decimal.zero
      , supplyDollarAmount = Decimal.zero
      , isApproved = False
      , historicalSwaps = []
      }
    , cmd
    )


type alias HistoricalSwap =
    { timeAgo : String
    , notional : String
    , rate : String
    , userPayingFixed : Bool
    , userPayout : Maybe String
    , swapHash : String
    }


type alias OrderInfoResponse =
    { swapRate : String
    , collatCToken : String
    , collatDollars : String
    , protocolIsCollateralized : Bool
    }



-- PORTS


port connect : () -> Cmd msg


port isConnected : () -> Cmd msg


port isApprovedCall : () -> Cmd msg


port approveSend : () -> Cmd msg


port supplyCTokensSend : String -> Cmd msg


port supplyToCTokensCall : String -> Cmd msg


port orderInfoCall : ( Bool, String ) -> Cmd msg


port swapHistory : () -> Cmd msg


port openSwapSend : ( Bool, String ) -> Cmd msg


port supplyBalance : () -> Cmd msg


port cTokenBalance : () -> Cmd msg


port closeSwapSend : String -> Cmd msg


port connectReceiver : (( String, String ) -> msg) -> Sub msg


port enableReceiver : (Bool -> msg) -> Sub msg


port supplyToCTokensReceiver : (String -> msg) -> Sub msg


port orderInfoReceiver : (OrderInfoResponse -> msg) -> Sub msg


port swapHistoryReceiver : (List HistoricalSwap -> msg) -> Sub msg


port userBalancesReceiver : (( String, String ) -> msg) -> Sub msg



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        tickCmd =
            case ( model.page, model.isApproved ) of
                ( App, False ) ->
                    Time.every 1000 Tick

                _ ->
                    Sub.none
    in
    Sub.batch
        [ connectReceiver HasConnected
        , enableReceiver Approved
        , supplyToCTokensReceiver SupplyCTokens
        , orderInfoReceiver OrderInfo
        , swapHistoryReceiver SwapHistory
        , userBalancesReceiver UserBalances
        , tickCmd
        ]



---- UPDATE ----


type Msg
    = NoOp
    | SelectModal Action
    | NotionalAmountInput String
    | OrderInfo OrderInfoResponse
    | Approved Bool
    | ApproveCmd
    | HasConnected ( String, String )
    | ConnectCmd
    | SupplyAmountInput String
    | SupplyCTokens String
    | SupplyTx
    | OpenTx
    | CloseTx String
    | Tick Time.Posix
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | TogglePayingFixed
    | IsUserConnected Bool
    | SwapHistory (List HistoricalSwap)
    | UserBalances ( String, String )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ConnectCmd ->
            ( model, connect () )

        HasConnected resp ->
            case resp of
                ( "invalid", "" ) ->
                    ( { model | connectionStatus = InvalidNetwork }, Cmd.none )

                ( "none", "" ) ->
                    ( { model | connectionStatus = NoMetamask }, Cmd.none )

                ( "unconnected", "" ) ->
                    ( { model | connectionStatus = NotConnected }, Cmd.none )

                ( network, addr ) ->
                    ( { model | connectionStatus = Connected { network = network, selectedAddr = addr } }, Cmd.none )

        SelectModal action ->
            case action of
                Close ->
                    ( { model | actionSelected = action }, swapHistory () )

                _ ->
                    ( { model | actionSelected = action }, Cmd.none )

        TogglePayingFixed ->
            let
                notionalStr =
                    Decimal.toString model.notionalAmount

                pf =
                    not model.isPayingFixed
            in
            ( { model | isPayingFixed = pf }, orderInfoCall ( pf, notionalStr ) )

        ApproveCmd ->
            ( model, approveSend () )

        Approved isApproved ->
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
            ( { model | notionalAmount = decAmt }, orderInfoCall ( model.isPayingFixed, strAmt ) )

        OrderInfo resp ->
            --( swapRate, collatCToken, collatDollars, isProtocolCollateralized ) ->
            let
                rate =
                    toDec resp.swapRate model.swapRate

                collatCTokenDec =
                    toDec resp.collatCToken model.collateralCTokens

                collatDollarDec =
                    toDec resp.collatDollars model.collateralDollars
            in
            ( { model | collateralCTokens = collatCTokenDec, swapRate = rate, collateralDollars = collatDollarDec }, Cmd.none )

        OpenTx ->
            ( model, openSwapSend ( model.isPayingFixed, Decimal.toString model.notionalAmount ) )

        CloseTx swapHash ->
            ( model, closeSwapSend swapHash )

        SwapHistory resp ->
            -- todo: put into decs
            ( { model | historicalSwaps = resp }, Cmd.none )

        UserBalances ( supplyBal, cTokenBal ) ->
            ( { model | supplyBalanceCToken = toDec supplyBal model.supplyBalanceCToken, cTokenBalance = toDec cTokenBal model.cTokenBalance }, Cmd.none )

        Tick _ ->
            ( model, Cmd.batch [ isApprovedCall () ] )

        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            let
                ( page, cmd, title ) =
                    getPage url
            in
            ( { model | page = page, title = title }, cmd )

        _ ->
            ( model, Cmd.none )



---- VIEW ----


view : Model -> Browser.Document Msg
view model =
    let
        body =
            case model.page of
                App ->
                    [ header model.connectionStatus True
                    , modal model
                    ]

                History ->
                    [ header model.connectionStatus True
                    , historyPage model.historicalSwaps model.collateral
                    ]

                Landing ->
                    [ header model.connectionStatus False
                    , landing (LandingStats True)
                    ]
    in
    { title = model.title
    , body = [ div [ id "container" ] body ]
    }


header : ConnectionStatus -> Bool -> Html Msg
header connectionStatus showMetamask =
    let
        metamaskBtn =
            case showMetamask of
                True ->
                    case connectionStatus of
                        Connected connection ->
                            div [ id "connected" ] [ text (connection.network ++ " " ++ String.slice 0 4 connection.selectedAddr ++ ".." ++ String.slice -4 -1 connection.selectedAddr) ]

                        NotConnected ->
                            button [ onClick ConnectCmd, class "ctaButton", id "connectButton" ] [ text "Connect Metamask" ]

                        InvalidNetwork ->
                            div [ id "connected" ] [ text "Invalid network" ]

                        NoMetamask ->
                            div [ id "connected" ] [ text "Need Metamask" ]

                False ->
                    div [] []
    in
    div [ id "header" ]
        [ a [ href "/" ]
            [ h1 [ id "logo" ] [ text "Rho%" ]
            ]
        , a [ href "/app", id "appNavButton" ] [ text "App" ]
        , a [ href "/history", id "historyNavButton" ] [ text "Swap History" ]
        , metamaskBtn
        ]


type alias LandingStats =
    { placeHolder : Bool }


landing : LandingStats -> Html Msg
landing stats =
    div [ id "modal" ]
        [ div
            [ class "landing-title" ]
            [ h3 [] [ text "Rho is a protocol for interest rate swaps" ] ]
        , ul [ class "landing-list" ] [ li [] [ text "You can use it for things" ] ]
        , button [ class "ctaButton", id "connectButton" ] [ a [ href "/app" ] [ text "App" ] ]
        ]


historyPage : List HistoricalSwap -> String -> Html Msg
historyPage swaps collatName =
    let
        title =
            [ h3 [ id "title" ] [ text "Swap History" ] ]

        elems =
            case swaps of
                [] ->
                    [ div [ class "modal-field" ] [ text "No account swap history" ] ]

                _ ->
                    List.map (historyElem collatName) swaps

        body =
            List.append title elems
    in
    div [ id "modal" ] body


historyElem : String -> HistoricalSwap -> Html Msg
historyElem collatName swap =
    let
        ( swapStatus, sinceOrPayout, titleClass ) =
            case swap.userPayout of
                Just p ->
                    ( "Closed", "earned " ++ p ++ " " ++ collatName, "swapTitleClosed" )

                Nothing ->
                    ( "Open", swap.timeAgo ++ " ago", "swapTitleOpen" )
    in
    div [ class "swapBox", class "modal-field" ]
        [ label [ class titleClass ] [ text swapStatus ]
        , label [] [ text (rateVerb swap.userPayingFixed True ++ " " ++ swap.rate ++ "% on " ++ swap.notional ++ " notional, " ++ sinceOrPayout) ]
        ]


modal : Model -> Html Msg
modal model =
    let
        action =
            model.actionSelected

        ctaButton =
            case model.isApproved of
                True ->
                    case action of
                        Open ->
                            button [ onClick OpenTx, class "ctaButton" ] [ text "Open Swap" ]

                        Supply ->
                            button [ onClick SupplyTx, class "ctaButton" ] [ text "Supply Liquidity" ]

                        _ ->
                            div [] []

                False ->
                    button [ onClick ApproveCmd, class "ctaButton" ] [ text ("Enable " ++ model.collateral) ]

        selectedModal =
            case action of
                Open ->
                    div [] [ openModal model, ctaButton ]

                Supply ->
                    div [] [ supplyModal model, ctaButton ]

                Close ->
                    div [] [ closeModal model ]

                _ ->
                    div [] []
    in
    div [ id "modal" ]
        [ h3 [ id "title" ] [ text (model.duration ++ " day " ++ model.collateral ++ " Interest Rate Swaps") ]
        , div [ id "buttonRow" ]
            [ selectorButton (action == Open) (SelectModal Open) "Open"
            , selectorButton (action == Close) (SelectModal Close) "Close"
            , selectorButton (action == Supply) (SelectModal Supply) "Supply"
            , selectorButton (action == Remove) (SelectModal Remove) "Remove"
            ]
        , selectedModal
        ]


supplyModal : Model -> Html Msg
supplyModal model =
    div [ class "form-elem" ]
        [ div [ class "modal-field" ] [ text ("Current Wallet Balance: " ++ Decimal.toString model.cTokenBalance ++ " cTokens") ]
        , div [ class "modal-field" ] [ text ("Current Supply Balance: " ++ (Decimal.toString model.supplyBalanceCToken ++ " cTokens")) ]
        , inputForm "Supply Amount : $" "0" (Decimal.toString model.supplyDollarAmount) SupplyAmountInput
        , div [ class "modal-field" ] [ text (Decimal.toString model.supplyCTokenAmount ++ " cTokens") ]
        ]


closeModal : Model -> Html Msg
closeModal model =
    let
        elems =
            case model.historicalSwaps of
                [] ->
                    [ div [ class "modal-field" ] [ text "No closeable swaps" ] ]

                swaps ->
                    List.map closeElem (List.filter (\swap -> swap.userPayout == Nothing) swaps)
    in
    div [] elems


closeElem : HistoricalSwap -> Html Msg
closeElem swap =
    button [ class "ctaButton", onClick (CloseTx swap.swapHash) ] [ text ("Close " ++ rateVerb swap.userPayingFixed True ++ " " ++ swap.rate ++ " on " ++ swap.notional ++ " notional") ]


rateVerb : Bool -> Bool -> String
rateVerb userPayingFixed isVerbForFixed =
    case userPayingFixed == isVerbForFixed of
        True ->
            "Pay"

        False ->
            "Receive"


openModal : Model -> Html Msg
openModal model =
    let
        fixedRateVerb =
            rateVerb model.isPayingFixed True

        floatRateVerb =
            rateVerb model.isPayingFixed False

        swapRateText =
            case Decimal.toString model.swapRate of
                "0" ->
                    "XX%"

                a ->
                    a ++ "%"

        collatText =
            "Collateral Required: $" ++ Decimal.toString model.collateralDollars ++ ", " ++ Decimal.toString model.collateralCTokens ++ " c" ++ model.underlying
    in
    div []
        [ div [ class "modal-field" ] [ text ("Current Wallet Balance: " ++ Decimal.toString model.cTokenBalance ++ " cTokens") ]
        , inputForm ("Notional Amount in " ++ model.underlying) "0" (Decimal.toString model.notionalAmount) NotionalAmountInput
        , div [ class "modal-field" ]
            [ button [ id "toggle-swap-type", onClick TogglePayingFixed ]
                [ label [] [ text fixedRateVerb ]
                , div [ class "gg-chevron-down" ] []
                ]
            , text ("  " ++ swapRateText ++ ", " ++ floatRateVerb ++ " cDAI borrow rate")
            ]
        , div [ class "modal-field" ] [ text collatText ]
        ]


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


main : Program Flags Model Msg
main =
    Browser.application
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }
