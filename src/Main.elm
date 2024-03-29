port module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Decimal exposing (Decimal)
import Html exposing (Html, a, button, div, footer, form, h1, h3, h4, input, label, li, option, select, text, ul)
import Html.Attributes exposing (attribute, class, height, href, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Time
import Url
import Url.Parser


type Page
    = App
    | History
    | Landing
    | Markets


defaultPage : Page
defaultPage =
    Landing


routeParser : Url.Parser.Parser (Page -> a) a
routeParser =
    Url.Parser.oneOf
        [ Url.Parser.map App (Url.Parser.s "app")
        , Url.Parser.map History (Url.Parser.s "history")
        , Url.Parser.map Markets (Url.Parser.s "markets")
        ]


getTitle : Page -> String
getTitle page =
    case page of
        App ->
            "Rho | App"

        History ->
            "Rho | History"

        Markets ->
            "Rho | Markets"

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

                Markets ->
                    getMarkets ()

                Landing ->
                    Cmd.none

        initTitle =
            getTitle page
    in
    ( page, cmd, initTitle )


type Action
    = Open
    | Close
    | Supply
    | Remove


type ConnectionStatus
    = Connected Web3Connection
    | NotConnected
    | InvalidNetwork
    | NoMetamask


type alias Flags =
    { underlying : String
    , collateral : String
    , duration : String
    , defaultNetwork : String
    }


type alias Web3Connection =
    { selectedAddr : String
    , network : String
    }


type alias HistoricalSwap =
    { timeAgo : String
    , notional : String
    , rate : String
    , userPayingFixed : Bool
    , userPayout : Maybe String
    , closeable : Bool
    , swapHash : String
    }



---- MODEL ----


type alias Model =
    { -- page stuff
      key : Nav.Key
    , page : Page
    , title : String
    , underlying : String
    , collateral : String
    , duration : String
    , defaultNetwork : String

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
    , supplyBalanceCToken : String
    , supplyBalanceDollars : Decimal
    , cTokenBalance : String
    , protocolCollateralized : Bool

    --supply modal form
    , supplyCTokenAmount : Decimal
    , supplyDollarAmount : Decimal
    , supplyUnderlying : String
    , isApproved : Bool
    , isAboveLimit : Bool

    --remove modal form
    , removeCTokenAmount : Decimal
    , removeDollarAmount : Decimal
    , unlockedLiquidity : String
    , isRepayingMax : Bool

    -- history page
    , historicalSwaps : List HistoricalSwap
    , marketData : MarketData
    }


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        ( page, cmds, title ) =
            getPage url
    in
    ( { key = key
      , page = page
      , title = title
      , underlying = flags.underlying
      , collateral = flags.collateral
      , duration = flags.duration
      , defaultNetwork = flags.defaultNetwork
      , protocolCollateralized = True
      , connectionStatus = NotConnected
      , actionSelected = Open
      , notionalAmount = Decimal.zero
      , collateralCTokens = Decimal.zero
      , collateralDollars = Decimal.zero
      , swapRate = Decimal.zero
      , isPayingFixed = True
      , supplyBalanceCToken = "-"
      , supplyBalanceDollars = Decimal.zero
      , isAboveLimit = False
      , supplyUnderlying = "-"
      , cTokenBalance = "-"
      , supplyCTokenAmount = Decimal.zero
      , supplyDollarAmount = Decimal.zero
      , removeCTokenAmount = Decimal.zero
      , removeDollarAmount = Decimal.zero
      , isRepayingMax = False
      , unlockedLiquidity = "-"
      , isApproved = False
      , historicalSwaps = []
      , marketData =
            { notionalReceivingFixed = "-"
            , notionalPayingFixed = "-"
            , lockedCollateral = "-"
            , supplierLiquidity = "-"
            , avgFixedRateReceiving = "-"
            , avgFixedRatePaying = "-"
            , liquidityLimit = "-"
            }
      }
    , cmds
    )


type alias OrderInfoResponse =
    { swapRate : String
    , collatCToken : String
    , collatDollars : String
    , protocolIsCollateralized : Bool
    }


type alias MarketData =
    { notionalReceivingFixed : String
    , notionalPayingFixed : String
    , supplierLiquidity : String
    , avgFixedRateReceiving : String
    , avgFixedRatePaying : String
    , lockedCollateral : String
    , liquidityLimit : String
    }


type alias UserBalancesResponse =
    { supplyBalanceCTokens : String
    , supplyBalanceUnderlying : String
    , userCTokenBalance : String
    }



-- PORTS


port connect : () -> Cmd msg


port isConnected : () -> Cmd msg


port isApprovedCall : () -> Cmd msg


port toCTokensCall : ( String, String ) -> Cmd msg


port orderInfoCall : ( Bool, String ) -> Cmd msg


port swapHistory : () -> Cmd msg


port supplyBalance : () -> Cmd msg


port cTokenBalance : () -> Cmd msg


port unlockedLiquidity : () -> Cmd msg


port approveSend : () -> Cmd msg


port supplyCTokensSend : String -> Cmd msg


port removeCTokensSend : ( String, Bool ) -> Cmd msg


port openSwapSend : ( Bool, String ) -> Cmd msg


port closeSwapSend : String -> Cmd msg


port getMarkets : () -> Cmd msg


port isAboveLimit : String -> Cmd msg


port connectReceiver : (( String, String ) -> msg) -> Sub msg


port enableReceiver : (Bool -> msg) -> Sub msg


port toCTokensReceiver : (( String, String ) -> msg) -> Sub msg


port orderInfoReceiver : (OrderInfoResponse -> msg) -> Sub msg


port swapHistoryReceiver : (List HistoricalSwap -> msg) -> Sub msg


port userBalancesReceiver : (UserBalancesResponse -> msg) -> Sub msg


port getMarketsReceiver : (MarketData -> msg) -> Sub msg


port unlockedLiquidityReceiver : (String -> msg) -> Sub msg


port aboveLimitReceiver : (Bool -> msg) -> Sub msg



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
        , toCTokensReceiver ToCTokens
        , orderInfoReceiver OrderInfo
        , swapHistoryReceiver SwapHistory
        , userBalancesReceiver UserBalances
        , getMarketsReceiver MarketsInfo
        , unlockedLiquidityReceiver UnlockedLiquidity
        , aboveLimitReceiver AboveLimit
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
    | RemoveAmountInput String
    | ToCTokens ( String, String )
    | SupplyTx
    | RemoveTx
    | OpenTx
    | CloseTx String
    | Tick Time.Posix
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | TogglePayingFixed
    | IsUserConnected Bool
    | SwapHistory (List HistoricalSwap)
    | UserBalances UserBalancesResponse
    | MarketsInfo MarketData
    | UnlockedLiquidity String
    | SetRepayingMax
    | AboveLimit Bool


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
            let
                selectedModel =
                    { model | actionSelected = action }
            in
            case action of
                Close ->
                    ( selectedModel, swapHistory () )

                Remove ->
                    ( selectedModel, Cmd.batch [ swapHistory (), unlockedLiquidity () ] )

                _ ->
                    ( selectedModel, Cmd.none )

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
            ( { model | supplyDollarAmount = decAmt }, Cmd.batch [ toCTokensCall ( "supply", strAmt ), isAboveLimit strAmt ] )

        RemoveAmountInput amt ->
            let
                ( decAmt, strAmt ) =
                    formatInput amt
            in
            ( { model | removeDollarAmount = decAmt, isRepayingMax = False }, toCTokensCall ( "remove", strAmt ) )

        ToCTokens ( name, ctokens ) ->
            case name of
                "supply" ->
                    ( { model | supplyCTokenAmount = toDec ctokens model.supplyCTokenAmount }, Cmd.none )

                "remove" ->
                    ( { model | removeCTokenAmount = toDec ctokens model.removeCTokenAmount }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        SupplyTx ->
            ( model, supplyCTokensSend (Decimal.toString model.supplyCTokenAmount) )

        SetRepayingMax ->
            ( { model | isRepayingMax = True, removeCTokenAmount = toDec model.supplyBalanceCToken model.removeCTokenAmount, removeDollarAmount = toDec model.supplyUnderlying model.removeDollarAmount }, Cmd.none )

        RemoveTx ->
            ( model, removeCTokensSend ( Decimal.toString model.removeCTokenAmount, model.isRepayingMax ) )

        NotionalAmountInput notional ->
            let
                ( decAmt, strAmt ) =
                    formatInput notional
            in
            ( { model | notionalAmount = decAmt }, Cmd.batch [ orderInfoCall ( model.isPayingFixed, strAmt ), isAboveLimit "0" ] )

        OrderInfo resp ->
            let
                rate =
                    toDec resp.swapRate model.swapRate

                collatCTokenDec =
                    toDec resp.collatCToken model.collateralCTokens

                collatDollarDec =
                    toDec resp.collatDollars model.collateralDollars
            in
            ( { model | collateralCTokens = collatCTokenDec, swapRate = rate, collateralDollars = collatDollarDec, protocolCollateralized = resp.protocolIsCollateralized }, Cmd.none )

        OpenTx ->
            ( model, openSwapSend ( model.isPayingFixed, Decimal.toString model.notionalAmount ) )

        CloseTx swapHash ->
            ( model, closeSwapSend swapHash )

        SwapHistory resp ->
            -- todo: put into decs
            ( { model | historicalSwaps = resp }, Cmd.none )

        UserBalances resp ->
            ( { model | supplyUnderlying = resp.supplyBalanceUnderlying, supplyBalanceCToken = resp.supplyBalanceCTokens, cTokenBalance = resp.userCTokenBalance }, Cmd.none )

        MarketsInfo resp ->
            ( { model | marketData = resp }, Cmd.none )

        UnlockedLiquidity unlocked ->
            ( { model | unlockedLiquidity = unlocked }, Cmd.none )

        AboveLimit aboveLim ->
            ( { model | isAboveLimit = aboveLim }, Cmd.none )

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
                    [ header model True
                    , modal model
                    ]

                History ->
                    [ header model True
                    , historyPage model.historicalSwaps model.collateral
                    ]

                Markets ->
                    [ header model False
                    , marketsPage model
                    ]

                Landing ->
                    [ header model False
                    , landing
                    ]
    in
    { title = model.title
    , body = [ div [ id "container" ] (List.append body [ footerDiv ]) ]
    }


header : Model -> Bool -> Html Msg
header model showMetamask =
    let
        metamaskBtn =
            case showMetamask of
                True ->
                    case model.connectionStatus of
                        Connected connection ->
                            let
                                netText =
                                    connection.network ++ " " ++ String.slice 0 4 connection.selectedAddr ++ ".." ++ String.slice -4 -1 connection.selectedAddr

                                collatText =
                                    model.cTokenBalance ++ " " ++ model.collateral
                            in
                            div [ id "connected" ] [ div [ id "connectElem" ] [ text netText ], div [ id "connectElem" ] [ text collatText ] ]

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
        , div [] []
        , a [ href "/app" ] [ text "App" ]
        , a [ href "/history" ] [ text "History" ]
        , a [ href "/markets" ] [ text "Markets" ]
        , metamaskBtn
        ]


landing : Html Msg
landing =
    div [ id "modal" ]
        [ div
            [ class "landing-title" ]
            [ h3 [] [ text "Rho" ] ]
        , ul [ class "landing-list" ]
            [ li [ class "warning" ]
                [ text "Experimental software in beta, use with caution" ]
            , li []
                [ text "Rho allows users to open interest rate swaps against a liquidity pool." ]
            , li []
                [ text "The floating leg is benchmarked against cDAI borrow rates." ]
            , li []
                [ text "Rho uses cDAI as collateral. "
                , a
                    [ class "underlineLink", href "https://app.compound.finance/" ]
                    [ text "Get cDAI here." ]
                ]
            , li []
                [ text "Swaps can be closed after 7 days." ]
            , li []
                [ text "After 7.5 days, keepers receive a fee for closing swaps." ]
            , li []
                [ a [ class "underlineLink", href "https://github.com/Rho-protocol/rho-docs" ] [ text "Learn more" ] ]
            ]
        , button [ class "ctaButton", id "connectButton" ] [ a [ href "/app" ] [ text "App" ] ]
        ]


marketsPage : Model -> Html Msg
marketsPage model =
    let
        marketData =
            model.marketData
    in
    div [ id "modal" ]
        [ h3 [ id "title" ] [ text "Market Overview" ]
        , div [ class "modal-field" ] [ text ("Protocol receiving fixed rate of " ++ marketData.avgFixedRateReceiving ++ "% on " ++ marketData.notionalReceivingFixed ++ " DAI") ]
        , div [ class "modal-field" ] [ text ("Protocol paying fixed rate of " ++ marketData.avgFixedRatePaying ++ "% on " ++ marketData.notionalPayingFixed ++ " DAI") ]
        , div [ class "modal-field" ] [ text ("Protocol has " ++ marketData.supplierLiquidity ++ " DAI of liquidity, " ++ marketData.lockedCollateral ++ " is locked in pending swaps") ]
        , div [ class "modal-field" ] [ text ("The liquidity limit is " ++ marketData.liquidityLimit ++ " DAI") ]
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

                        Remove ->
                            button [ onClick RemoveTx, class "ctaButton" ] [ text "Remove Liquidity" ]

                        _ ->
                            div [] []

                False ->
                    button [ onClick ApproveCmd, class "ctaButton" ] [ text ("Enable " ++ model.collateral) ]

        liquidityLimit =
            div [ class "modal-field", class "warning" ] [ text "Above Liquidity Safety Limit, Action Paused" ]

        selectedModal =
            case ( action, model.isAboveLimit ) of
                ( Open, False ) ->
                    div [] [ openModal model, ctaButton ]

                ( Supply, False ) ->
                    div [] [ supplyModal model, ctaButton ]

                ( Open, True ) ->
                    div [] [ openModal model, liquidityLimit ]

                ( Supply, True ) ->
                    div [] [ supplyModal model, liquidityLimit ]

                ( Close, _ ) ->
                    div [] [ closeModal model, ctaButton ]

                ( Remove, _ ) ->
                    div [] [ removeModal model, ctaButton ]
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
        [ userSupplyField model
        , inputForm "Supply Amount : $" "0" (Decimal.toString model.supplyDollarAmount) SupplyAmountInput
        , div [ class "modal-field" ] [ text ("Supply: " ++ Decimal.toString model.supplyCTokenAmount ++ " " ++ model.collateral) ]
        ]


removeModal : Model -> Html Msg
removeModal model =
    div [ class "form-elem" ]
        [ userSupplyField model
        , div [ class "modal-field" ] [ text ("Liquidity Available: " ++ model.unlockedLiquidity ++ " " ++ model.underlying) ]
        , div [ class "modal-field" ]
            [ label []
                [ text "Remove Amount : $"
                , input [ type_ "number", attribute "placeholder" "0", value (Decimal.toString model.removeDollarAmount), onInput RemoveAmountInput, attribute "autofocus" "autofocus" ] []
                ]
            , button [ id "toggle-remove-max", onClick SetRepayingMax ] [ text "max" ]
            ]
        , div [ class "modal-field" ] [ text ("Remove: " ++ Decimal.toString model.removeCTokenAmount ++ " " ++ model.collateral) ]
        ]


userSupplyField : Model -> Html Msg
userSupplyField model =
    div [ class "modal-field" ] [ text ("Supply Balance: $" ++ model.supplyUnderlying ++ " (" ++ model.supplyBalanceCToken ++ " " ++ model.collateral ++ ")") ]


closeModal : Model -> Html Msg
closeModal model =
    let
        closeable =
            List.filter (\swap -> swap.closeable == True) model.historicalSwaps

        elems =
            case closeable of
                [] ->
                    [ div [ class "modal-field" ] [ text "No closeable swaps" ] ]

                swaps ->
                    List.map closeElem closeable
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

        collatField =
            case model.protocolCollateralized of
                False ->
                    div [ class "modal-field", class "warning" ] [ text "Insufficient protocol collateral" ]

                True ->
                    let
                        str =
                            String.concat
                                [ "Collateral Required: $"
                                , Decimal.toString model.collateralDollars
                                , ", "
                                , Decimal.toString model.collateralCTokens
                                , " "
                                , model.collateral
                                ]
                    in
                    div [ class "modal-field" ] [ text str ]
    in
    div []
        [ inputForm ("Notional Amount in " ++ model.underlying) "0" (Decimal.toString model.notionalAmount) NotionalAmountInput
        , div [ class "modal-field" ]
            [ button [ id "toggle-swap-type", onClick TogglePayingFixed ]
                [ label [] [ text fixedRateVerb ]
                , div [ class "gg-chevron-down" ] []
                ]
            , text ("  " ++ swapRateText ++ ", " ++ floatRateVerb ++ " " ++ model.collateral ++ " borrow rate")
            ]
        , collatField
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


footerDiv : Html Msg
footerDiv =
    ul [ id "footer" ]
        [ li [ class "footer-elem" ] [ a [ href "https://twitter.com/rho_finance" ] [ text "Twitter " ] ]
        , li [ class "footer-elem" ] [ a [ href "https://github.com/Rho-protocol" ] [ text "Github " ] ]
        , li [ class "footer-elem" ] [ a [ href "https://discord.gg/Pvhn5fTVsm" ] [ text "Discord " ] ]
        , li [ class "footer-elem" ] [ a [ href "https://github.com/Rho-protocol/rho-docs" ] [ text "Docs " ] ]
        ]


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
