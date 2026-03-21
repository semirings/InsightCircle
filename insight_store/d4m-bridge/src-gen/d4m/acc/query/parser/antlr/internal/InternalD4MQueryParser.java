package d4m.acc.query.parser.antlr.internal;

import org.eclipse.xtext.*;
import org.eclipse.xtext.parser.*;
import org.eclipse.xtext.parser.impl.*;
import org.eclipse.emf.ecore.util.EcoreUtil;
import org.eclipse.emf.ecore.EObject;
import org.eclipse.xtext.parser.antlr.AbstractInternalAntlrParser;
import org.eclipse.xtext.parser.antlr.XtextTokenStream;
import org.eclipse.xtext.parser.antlr.XtextTokenStream.HiddenTokens;
import org.eclipse.xtext.parser.antlr.AntlrDatatypeRuleToken;
import d4m.acc.query.services.D4MQueryGrammarAccess;



import org.antlr.runtime.*;
import java.util.Stack;
import java.util.List;
import java.util.ArrayList;

@SuppressWarnings("all")
public class InternalD4MQueryParser extends AbstractInternalAntlrParser {
    public static final String[] tokenNames = new String[] {
        "<invalid>", "<EOR>", "<DOWN>", "<UP>", "RULE_STRING", "RULE_ID", "RULE_INT", "RULE_ML_COMMENT", "RULE_SL_COMMENT", "RULE_WS", "RULE_ANY_OTHER", "','", "':'", "'..'", "'['", "']'", "'StartsWith'", "'('", "')'", "'Regex'"
    };
    public static final int RULE_STRING=4;
    public static final int RULE_SL_COMMENT=8;
    public static final int T__19=19;
    public static final int T__15=15;
    public static final int T__16=16;
    public static final int T__17=17;
    public static final int T__18=18;
    public static final int T__11=11;
    public static final int T__12=12;
    public static final int T__13=13;
    public static final int T__14=14;
    public static final int EOF=-1;
    public static final int RULE_ID=5;
    public static final int RULE_WS=9;
    public static final int RULE_ANY_OTHER=10;
    public static final int RULE_INT=6;
    public static final int RULE_ML_COMMENT=7;

    // delegates
    // delegators


        public InternalD4MQueryParser(TokenStream input) {
            this(input, new RecognizerSharedState());
        }
        public InternalD4MQueryParser(TokenStream input, RecognizerSharedState state) {
            super(input, state);
             
        }
        

    public String[] getTokenNames() { return InternalD4MQueryParser.tokenNames; }
    public String getGrammarFileName() { return "InternalD4MQuery.g"; }



     	private D4MQueryGrammarAccess grammarAccess;

        public InternalD4MQueryParser(TokenStream input, D4MQueryGrammarAccess grammarAccess) {
            this(input);
            this.grammarAccess = grammarAccess;
            registerRules(grammarAccess.getGrammar());
        }

        @Override
        protected String getFirstRuleName() {
        	return "D4MQuery";
       	}

       	@Override
       	protected D4MQueryGrammarAccess getGrammarAccess() {
       		return grammarAccess;
       	}




    // $ANTLR start "entryRuleD4MQuery"
    // InternalD4MQuery.g:64:1: entryRuleD4MQuery returns [EObject current=null] : iv_ruleD4MQuery= ruleD4MQuery EOF ;
    public final EObject entryRuleD4MQuery() throws RecognitionException {
        EObject current = null;

        EObject iv_ruleD4MQuery = null;


        try {
            // InternalD4MQuery.g:64:49: (iv_ruleD4MQuery= ruleD4MQuery EOF )
            // InternalD4MQuery.g:65:2: iv_ruleD4MQuery= ruleD4MQuery EOF
            {
             newCompositeNode(grammarAccess.getD4MQueryRule()); 
            pushFollow(FOLLOW_1);
            iv_ruleD4MQuery=ruleD4MQuery();

            state._fsp--;

             current =iv_ruleD4MQuery; 
            match(input,EOF,FOLLOW_2); 

            }

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "entryRuleD4MQuery"


    // $ANTLR start "ruleD4MQuery"
    // InternalD4MQuery.g:71:1: ruleD4MQuery returns [EObject current=null] : ( (lv_query_0_0= ruleQueryExpr ) ) ;
    public final EObject ruleD4MQuery() throws RecognitionException {
        EObject current = null;

        EObject lv_query_0_0 = null;



        	enterRule();

        try {
            // InternalD4MQuery.g:77:2: ( ( (lv_query_0_0= ruleQueryExpr ) ) )
            // InternalD4MQuery.g:78:2: ( (lv_query_0_0= ruleQueryExpr ) )
            {
            // InternalD4MQuery.g:78:2: ( (lv_query_0_0= ruleQueryExpr ) )
            // InternalD4MQuery.g:79:3: (lv_query_0_0= ruleQueryExpr )
            {
            // InternalD4MQuery.g:79:3: (lv_query_0_0= ruleQueryExpr )
            // InternalD4MQuery.g:80:4: lv_query_0_0= ruleQueryExpr
            {

            				newCompositeNode(grammarAccess.getD4MQueryAccess().getQueryQueryExprParserRuleCall_0());
            			
            pushFollow(FOLLOW_2);
            lv_query_0_0=ruleQueryExpr();

            state._fsp--;


            				if (current==null) {
            					current = createModelElementForParent(grammarAccess.getD4MQueryRule());
            				}
            				set(
            					current,
            					"query",
            					lv_query_0_0,
            					"d4m.acc.query.D4MQuery.QueryExpr");
            				afterParserOrEnumRuleCall();
            			

            }


            }


            }


            	leaveRule();

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "ruleD4MQuery"


    // $ANTLR start "entryRuleQueryExpr"
    // InternalD4MQuery.g:100:1: entryRuleQueryExpr returns [EObject current=null] : iv_ruleQueryExpr= ruleQueryExpr EOF ;
    public final EObject entryRuleQueryExpr() throws RecognitionException {
        EObject current = null;

        EObject iv_ruleQueryExpr = null;


        try {
            // InternalD4MQuery.g:100:50: (iv_ruleQueryExpr= ruleQueryExpr EOF )
            // InternalD4MQuery.g:101:2: iv_ruleQueryExpr= ruleQueryExpr EOF
            {
             newCompositeNode(grammarAccess.getQueryExprRule()); 
            pushFollow(FOLLOW_1);
            iv_ruleQueryExpr=ruleQueryExpr();

            state._fsp--;

             current =iv_ruleQueryExpr; 
            match(input,EOF,FOLLOW_2); 

            }

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "entryRuleQueryExpr"


    // $ANTLR start "ruleQueryExpr"
    // InternalD4MQuery.g:107:1: ruleQueryExpr returns [EObject current=null] : ( ( (lv_row_0_0= ruleAxisExpr ) ) otherlv_1= ',' ( (lv_col_2_0= ruleAxisExpr ) ) ) ;
    public final EObject ruleQueryExpr() throws RecognitionException {
        EObject current = null;

        Token otherlv_1=null;
        EObject lv_row_0_0 = null;

        EObject lv_col_2_0 = null;



        	enterRule();

        try {
            // InternalD4MQuery.g:113:2: ( ( ( (lv_row_0_0= ruleAxisExpr ) ) otherlv_1= ',' ( (lv_col_2_0= ruleAxisExpr ) ) ) )
            // InternalD4MQuery.g:114:2: ( ( (lv_row_0_0= ruleAxisExpr ) ) otherlv_1= ',' ( (lv_col_2_0= ruleAxisExpr ) ) )
            {
            // InternalD4MQuery.g:114:2: ( ( (lv_row_0_0= ruleAxisExpr ) ) otherlv_1= ',' ( (lv_col_2_0= ruleAxisExpr ) ) )
            // InternalD4MQuery.g:115:3: ( (lv_row_0_0= ruleAxisExpr ) ) otherlv_1= ',' ( (lv_col_2_0= ruleAxisExpr ) )
            {
            // InternalD4MQuery.g:115:3: ( (lv_row_0_0= ruleAxisExpr ) )
            // InternalD4MQuery.g:116:4: (lv_row_0_0= ruleAxisExpr )
            {
            // InternalD4MQuery.g:116:4: (lv_row_0_0= ruleAxisExpr )
            // InternalD4MQuery.g:117:5: lv_row_0_0= ruleAxisExpr
            {

            					newCompositeNode(grammarAccess.getQueryExprAccess().getRowAxisExprParserRuleCall_0_0());
            				
            pushFollow(FOLLOW_3);
            lv_row_0_0=ruleAxisExpr();

            state._fsp--;


            					if (current==null) {
            						current = createModelElementForParent(grammarAccess.getQueryExprRule());
            					}
            					set(
            						current,
            						"row",
            						lv_row_0_0,
            						"d4m.acc.query.D4MQuery.AxisExpr");
            					afterParserOrEnumRuleCall();
            				

            }


            }

            otherlv_1=(Token)match(input,11,FOLLOW_4); 

            			newLeafNode(otherlv_1, grammarAccess.getQueryExprAccess().getCommaKeyword_1());
            		
            // InternalD4MQuery.g:138:3: ( (lv_col_2_0= ruleAxisExpr ) )
            // InternalD4MQuery.g:139:4: (lv_col_2_0= ruleAxisExpr )
            {
            // InternalD4MQuery.g:139:4: (lv_col_2_0= ruleAxisExpr )
            // InternalD4MQuery.g:140:5: lv_col_2_0= ruleAxisExpr
            {

            					newCompositeNode(grammarAccess.getQueryExprAccess().getColAxisExprParserRuleCall_2_0());
            				
            pushFollow(FOLLOW_2);
            lv_col_2_0=ruleAxisExpr();

            state._fsp--;


            					if (current==null) {
            						current = createModelElementForParent(grammarAccess.getQueryExprRule());
            					}
            					set(
            						current,
            						"col",
            						lv_col_2_0,
            						"d4m.acc.query.D4MQuery.AxisExpr");
            					afterParserOrEnumRuleCall();
            				

            }


            }


            }


            }


            	leaveRule();

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "ruleQueryExpr"


    // $ANTLR start "entryRuleAxisExpr"
    // InternalD4MQuery.g:161:1: entryRuleAxisExpr returns [EObject current=null] : iv_ruleAxisExpr= ruleAxisExpr EOF ;
    public final EObject entryRuleAxisExpr() throws RecognitionException {
        EObject current = null;

        EObject iv_ruleAxisExpr = null;


        try {
            // InternalD4MQuery.g:161:49: (iv_ruleAxisExpr= ruleAxisExpr EOF )
            // InternalD4MQuery.g:162:2: iv_ruleAxisExpr= ruleAxisExpr EOF
            {
             newCompositeNode(grammarAccess.getAxisExprRule()); 
            pushFollow(FOLLOW_1);
            iv_ruleAxisExpr=ruleAxisExpr();

            state._fsp--;

             current =iv_ruleAxisExpr; 
            match(input,EOF,FOLLOW_2); 

            }

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "entryRuleAxisExpr"


    // $ANTLR start "ruleAxisExpr"
    // InternalD4MQuery.g:168:1: ruleAxisExpr returns [EObject current=null] : (this_RowColWildcard_0= ruleRowColWildcard | this_RangeExpr_1= ruleRangeExpr | this_ListExpr_2= ruleListExpr | this_StartsWithExpr_3= ruleStartsWithExpr | this_RegexExpr_4= ruleRegexExpr | this_LiteralExpr_5= ruleLiteralExpr ) ;
    public final EObject ruleAxisExpr() throws RecognitionException {
        EObject current = null;

        EObject this_RowColWildcard_0 = null;

        EObject this_RangeExpr_1 = null;

        EObject this_ListExpr_2 = null;

        EObject this_StartsWithExpr_3 = null;

        EObject this_RegexExpr_4 = null;

        EObject this_LiteralExpr_5 = null;



        	enterRule();

        try {
            // InternalD4MQuery.g:174:2: ( (this_RowColWildcard_0= ruleRowColWildcard | this_RangeExpr_1= ruleRangeExpr | this_ListExpr_2= ruleListExpr | this_StartsWithExpr_3= ruleStartsWithExpr | this_RegexExpr_4= ruleRegexExpr | this_LiteralExpr_5= ruleLiteralExpr ) )
            // InternalD4MQuery.g:175:2: (this_RowColWildcard_0= ruleRowColWildcard | this_RangeExpr_1= ruleRangeExpr | this_ListExpr_2= ruleListExpr | this_StartsWithExpr_3= ruleStartsWithExpr | this_RegexExpr_4= ruleRegexExpr | this_LiteralExpr_5= ruleLiteralExpr )
            {
            // InternalD4MQuery.g:175:2: (this_RowColWildcard_0= ruleRowColWildcard | this_RangeExpr_1= ruleRangeExpr | this_ListExpr_2= ruleListExpr | this_StartsWithExpr_3= ruleStartsWithExpr | this_RegexExpr_4= ruleRegexExpr | this_LiteralExpr_5= ruleLiteralExpr )
            int alt1=6;
            switch ( input.LA(1) ) {
            case 12:
                {
                alt1=1;
                }
                break;
            case RULE_STRING:
                {
                int LA1_2 = input.LA(2);

                if ( (LA1_2==EOF||LA1_2==11) ) {
                    alt1=6;
                }
                else if ( (LA1_2==13) ) {
                    alt1=2;
                }
                else {
                    NoViableAltException nvae =
                        new NoViableAltException("", 1, 2, input);

                    throw nvae;
                }
                }
                break;
            case 14:
                {
                alt1=3;
                }
                break;
            case 16:
                {
                alt1=4;
                }
                break;
            case 19:
                {
                alt1=5;
                }
                break;
            case RULE_ID:
                {
                alt1=6;
                }
                break;
            default:
                NoViableAltException nvae =
                    new NoViableAltException("", 1, 0, input);

                throw nvae;
            }

            switch (alt1) {
                case 1 :
                    // InternalD4MQuery.g:176:3: this_RowColWildcard_0= ruleRowColWildcard
                    {

                    			newCompositeNode(grammarAccess.getAxisExprAccess().getRowColWildcardParserRuleCall_0());
                    		
                    pushFollow(FOLLOW_2);
                    this_RowColWildcard_0=ruleRowColWildcard();

                    state._fsp--;


                    			current = this_RowColWildcard_0;
                    			afterParserOrEnumRuleCall();
                    		

                    }
                    break;
                case 2 :
                    // InternalD4MQuery.g:185:3: this_RangeExpr_1= ruleRangeExpr
                    {

                    			newCompositeNode(grammarAccess.getAxisExprAccess().getRangeExprParserRuleCall_1());
                    		
                    pushFollow(FOLLOW_2);
                    this_RangeExpr_1=ruleRangeExpr();

                    state._fsp--;


                    			current = this_RangeExpr_1;
                    			afterParserOrEnumRuleCall();
                    		

                    }
                    break;
                case 3 :
                    // InternalD4MQuery.g:194:3: this_ListExpr_2= ruleListExpr
                    {

                    			newCompositeNode(grammarAccess.getAxisExprAccess().getListExprParserRuleCall_2());
                    		
                    pushFollow(FOLLOW_2);
                    this_ListExpr_2=ruleListExpr();

                    state._fsp--;


                    			current = this_ListExpr_2;
                    			afterParserOrEnumRuleCall();
                    		

                    }
                    break;
                case 4 :
                    // InternalD4MQuery.g:203:3: this_StartsWithExpr_3= ruleStartsWithExpr
                    {

                    			newCompositeNode(grammarAccess.getAxisExprAccess().getStartsWithExprParserRuleCall_3());
                    		
                    pushFollow(FOLLOW_2);
                    this_StartsWithExpr_3=ruleStartsWithExpr();

                    state._fsp--;


                    			current = this_StartsWithExpr_3;
                    			afterParserOrEnumRuleCall();
                    		

                    }
                    break;
                case 5 :
                    // InternalD4MQuery.g:212:3: this_RegexExpr_4= ruleRegexExpr
                    {

                    			newCompositeNode(grammarAccess.getAxisExprAccess().getRegexExprParserRuleCall_4());
                    		
                    pushFollow(FOLLOW_2);
                    this_RegexExpr_4=ruleRegexExpr();

                    state._fsp--;


                    			current = this_RegexExpr_4;
                    			afterParserOrEnumRuleCall();
                    		

                    }
                    break;
                case 6 :
                    // InternalD4MQuery.g:221:3: this_LiteralExpr_5= ruleLiteralExpr
                    {

                    			newCompositeNode(grammarAccess.getAxisExprAccess().getLiteralExprParserRuleCall_5());
                    		
                    pushFollow(FOLLOW_2);
                    this_LiteralExpr_5=ruleLiteralExpr();

                    state._fsp--;


                    			current = this_LiteralExpr_5;
                    			afterParserOrEnumRuleCall();
                    		

                    }
                    break;

            }


            }


            	leaveRule();

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "ruleAxisExpr"


    // $ANTLR start "entryRuleRowColWildcard"
    // InternalD4MQuery.g:233:1: entryRuleRowColWildcard returns [EObject current=null] : iv_ruleRowColWildcard= ruleRowColWildcard EOF ;
    public final EObject entryRuleRowColWildcard() throws RecognitionException {
        EObject current = null;

        EObject iv_ruleRowColWildcard = null;


        try {
            // InternalD4MQuery.g:233:55: (iv_ruleRowColWildcard= ruleRowColWildcard EOF )
            // InternalD4MQuery.g:234:2: iv_ruleRowColWildcard= ruleRowColWildcard EOF
            {
             newCompositeNode(grammarAccess.getRowColWildcardRule()); 
            pushFollow(FOLLOW_1);
            iv_ruleRowColWildcard=ruleRowColWildcard();

            state._fsp--;

             current =iv_ruleRowColWildcard; 
            match(input,EOF,FOLLOW_2); 

            }

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "entryRuleRowColWildcard"


    // $ANTLR start "ruleRowColWildcard"
    // InternalD4MQuery.g:240:1: ruleRowColWildcard returns [EObject current=null] : ( () otherlv_1= ':' ) ;
    public final EObject ruleRowColWildcard() throws RecognitionException {
        EObject current = null;

        Token otherlv_1=null;


        	enterRule();

        try {
            // InternalD4MQuery.g:246:2: ( ( () otherlv_1= ':' ) )
            // InternalD4MQuery.g:247:2: ( () otherlv_1= ':' )
            {
            // InternalD4MQuery.g:247:2: ( () otherlv_1= ':' )
            // InternalD4MQuery.g:248:3: () otherlv_1= ':'
            {
            // InternalD4MQuery.g:248:3: ()
            // InternalD4MQuery.g:249:4: 
            {

            				current = forceCreateModelElement(
            					grammarAccess.getRowColWildcardAccess().getRowColWildcardAction_0(),
            					current);
            			

            }

            otherlv_1=(Token)match(input,12,FOLLOW_2); 

            			newLeafNode(otherlv_1, grammarAccess.getRowColWildcardAccess().getColonKeyword_1());
            		

            }


            }


            	leaveRule();

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "ruleRowColWildcard"


    // $ANTLR start "entryRuleRangeExpr"
    // InternalD4MQuery.g:263:1: entryRuleRangeExpr returns [EObject current=null] : iv_ruleRangeExpr= ruleRangeExpr EOF ;
    public final EObject entryRuleRangeExpr() throws RecognitionException {
        EObject current = null;

        EObject iv_ruleRangeExpr = null;


        try {
            // InternalD4MQuery.g:263:50: (iv_ruleRangeExpr= ruleRangeExpr EOF )
            // InternalD4MQuery.g:264:2: iv_ruleRangeExpr= ruleRangeExpr EOF
            {
             newCompositeNode(grammarAccess.getRangeExprRule()); 
            pushFollow(FOLLOW_1);
            iv_ruleRangeExpr=ruleRangeExpr();

            state._fsp--;

             current =iv_ruleRangeExpr; 
            match(input,EOF,FOLLOW_2); 

            }

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "entryRuleRangeExpr"


    // $ANTLR start "ruleRangeExpr"
    // InternalD4MQuery.g:270:1: ruleRangeExpr returns [EObject current=null] : ( ( (lv_from_0_0= RULE_STRING ) ) otherlv_1= '..' ( (lv_to_2_0= RULE_STRING ) ) ) ;
    public final EObject ruleRangeExpr() throws RecognitionException {
        EObject current = null;

        Token lv_from_0_0=null;
        Token otherlv_1=null;
        Token lv_to_2_0=null;


        	enterRule();

        try {
            // InternalD4MQuery.g:276:2: ( ( ( (lv_from_0_0= RULE_STRING ) ) otherlv_1= '..' ( (lv_to_2_0= RULE_STRING ) ) ) )
            // InternalD4MQuery.g:277:2: ( ( (lv_from_0_0= RULE_STRING ) ) otherlv_1= '..' ( (lv_to_2_0= RULE_STRING ) ) )
            {
            // InternalD4MQuery.g:277:2: ( ( (lv_from_0_0= RULE_STRING ) ) otherlv_1= '..' ( (lv_to_2_0= RULE_STRING ) ) )
            // InternalD4MQuery.g:278:3: ( (lv_from_0_0= RULE_STRING ) ) otherlv_1= '..' ( (lv_to_2_0= RULE_STRING ) )
            {
            // InternalD4MQuery.g:278:3: ( (lv_from_0_0= RULE_STRING ) )
            // InternalD4MQuery.g:279:4: (lv_from_0_0= RULE_STRING )
            {
            // InternalD4MQuery.g:279:4: (lv_from_0_0= RULE_STRING )
            // InternalD4MQuery.g:280:5: lv_from_0_0= RULE_STRING
            {
            lv_from_0_0=(Token)match(input,RULE_STRING,FOLLOW_5); 

            					newLeafNode(lv_from_0_0, grammarAccess.getRangeExprAccess().getFromSTRINGTerminalRuleCall_0_0());
            				

            					if (current==null) {
            						current = createModelElement(grammarAccess.getRangeExprRule());
            					}
            					setWithLastConsumed(
            						current,
            						"from",
            						lv_from_0_0,
            						"org.eclipse.xtext.common.Terminals.STRING");
            				

            }


            }

            otherlv_1=(Token)match(input,13,FOLLOW_6); 

            			newLeafNode(otherlv_1, grammarAccess.getRangeExprAccess().getFullStopFullStopKeyword_1());
            		
            // InternalD4MQuery.g:300:3: ( (lv_to_2_0= RULE_STRING ) )
            // InternalD4MQuery.g:301:4: (lv_to_2_0= RULE_STRING )
            {
            // InternalD4MQuery.g:301:4: (lv_to_2_0= RULE_STRING )
            // InternalD4MQuery.g:302:5: lv_to_2_0= RULE_STRING
            {
            lv_to_2_0=(Token)match(input,RULE_STRING,FOLLOW_2); 

            					newLeafNode(lv_to_2_0, grammarAccess.getRangeExprAccess().getToSTRINGTerminalRuleCall_2_0());
            				

            					if (current==null) {
            						current = createModelElement(grammarAccess.getRangeExprRule());
            					}
            					setWithLastConsumed(
            						current,
            						"to",
            						lv_to_2_0,
            						"org.eclipse.xtext.common.Terminals.STRING");
            				

            }


            }


            }


            }


            	leaveRule();

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "ruleRangeExpr"


    // $ANTLR start "entryRuleListExpr"
    // InternalD4MQuery.g:322:1: entryRuleListExpr returns [EObject current=null] : iv_ruleListExpr= ruleListExpr EOF ;
    public final EObject entryRuleListExpr() throws RecognitionException {
        EObject current = null;

        EObject iv_ruleListExpr = null;


        try {
            // InternalD4MQuery.g:322:49: (iv_ruleListExpr= ruleListExpr EOF )
            // InternalD4MQuery.g:323:2: iv_ruleListExpr= ruleListExpr EOF
            {
             newCompositeNode(grammarAccess.getListExprRule()); 
            pushFollow(FOLLOW_1);
            iv_ruleListExpr=ruleListExpr();

            state._fsp--;

             current =iv_ruleListExpr; 
            match(input,EOF,FOLLOW_2); 

            }

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "entryRuleListExpr"


    // $ANTLR start "ruleListExpr"
    // InternalD4MQuery.g:329:1: ruleListExpr returns [EObject current=null] : (otherlv_0= '[' ( ( (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID ) ) ) (otherlv_2= ',' ( ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) ) ) )* otherlv_4= ']' ) ;
    public final EObject ruleListExpr() throws RecognitionException {
        EObject current = null;

        Token otherlv_0=null;
        Token lv_values_1_1=null;
        Token lv_values_1_2=null;
        Token otherlv_2=null;
        Token lv_values_3_1=null;
        Token lv_values_3_2=null;
        Token otherlv_4=null;


        	enterRule();

        try {
            // InternalD4MQuery.g:335:2: ( (otherlv_0= '[' ( ( (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID ) ) ) (otherlv_2= ',' ( ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) ) ) )* otherlv_4= ']' ) )
            // InternalD4MQuery.g:336:2: (otherlv_0= '[' ( ( (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID ) ) ) (otherlv_2= ',' ( ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) ) ) )* otherlv_4= ']' )
            {
            // InternalD4MQuery.g:336:2: (otherlv_0= '[' ( ( (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID ) ) ) (otherlv_2= ',' ( ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) ) ) )* otherlv_4= ']' )
            // InternalD4MQuery.g:337:3: otherlv_0= '[' ( ( (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID ) ) ) (otherlv_2= ',' ( ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) ) ) )* otherlv_4= ']'
            {
            otherlv_0=(Token)match(input,14,FOLLOW_7); 

            			newLeafNode(otherlv_0, grammarAccess.getListExprAccess().getLeftSquareBracketKeyword_0());
            		
            // InternalD4MQuery.g:341:3: ( ( (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID ) ) )
            // InternalD4MQuery.g:342:4: ( (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID ) )
            {
            // InternalD4MQuery.g:342:4: ( (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID ) )
            // InternalD4MQuery.g:343:5: (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID )
            {
            // InternalD4MQuery.g:343:5: (lv_values_1_1= RULE_STRING | lv_values_1_2= RULE_ID )
            int alt2=2;
            int LA2_0 = input.LA(1);

            if ( (LA2_0==RULE_STRING) ) {
                alt2=1;
            }
            else if ( (LA2_0==RULE_ID) ) {
                alt2=2;
            }
            else {
                NoViableAltException nvae =
                    new NoViableAltException("", 2, 0, input);

                throw nvae;
            }
            switch (alt2) {
                case 1 :
                    // InternalD4MQuery.g:344:6: lv_values_1_1= RULE_STRING
                    {
                    lv_values_1_1=(Token)match(input,RULE_STRING,FOLLOW_8); 

                    						newLeafNode(lv_values_1_1, grammarAccess.getListExprAccess().getValuesSTRINGTerminalRuleCall_1_0_0());
                    					

                    						if (current==null) {
                    							current = createModelElement(grammarAccess.getListExprRule());
                    						}
                    						addWithLastConsumed(
                    							current,
                    							"values",
                    							lv_values_1_1,
                    							"org.eclipse.xtext.common.Terminals.STRING");
                    					

                    }
                    break;
                case 2 :
                    // InternalD4MQuery.g:359:6: lv_values_1_2= RULE_ID
                    {
                    lv_values_1_2=(Token)match(input,RULE_ID,FOLLOW_8); 

                    						newLeafNode(lv_values_1_2, grammarAccess.getListExprAccess().getValuesIDTerminalRuleCall_1_0_1());
                    					

                    						if (current==null) {
                    							current = createModelElement(grammarAccess.getListExprRule());
                    						}
                    						addWithLastConsumed(
                    							current,
                    							"values",
                    							lv_values_1_2,
                    							"d4m.acc.query.D4MQuery.ID");
                    					

                    }
                    break;

            }


            }


            }

            // InternalD4MQuery.g:376:3: (otherlv_2= ',' ( ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) ) ) )*
            loop4:
            do {
                int alt4=2;
                int LA4_0 = input.LA(1);

                if ( (LA4_0==11) ) {
                    alt4=1;
                }


                switch (alt4) {
            	case 1 :
            	    // InternalD4MQuery.g:377:4: otherlv_2= ',' ( ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) ) )
            	    {
            	    otherlv_2=(Token)match(input,11,FOLLOW_7); 

            	    				newLeafNode(otherlv_2, grammarAccess.getListExprAccess().getCommaKeyword_2_0());
            	    			
            	    // InternalD4MQuery.g:381:4: ( ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) ) )
            	    // InternalD4MQuery.g:382:5: ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) )
            	    {
            	    // InternalD4MQuery.g:382:5: ( (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID ) )
            	    // InternalD4MQuery.g:383:6: (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID )
            	    {
            	    // InternalD4MQuery.g:383:6: (lv_values_3_1= RULE_STRING | lv_values_3_2= RULE_ID )
            	    int alt3=2;
            	    int LA3_0 = input.LA(1);

            	    if ( (LA3_0==RULE_STRING) ) {
            	        alt3=1;
            	    }
            	    else if ( (LA3_0==RULE_ID) ) {
            	        alt3=2;
            	    }
            	    else {
            	        NoViableAltException nvae =
            	            new NoViableAltException("", 3, 0, input);

            	        throw nvae;
            	    }
            	    switch (alt3) {
            	        case 1 :
            	            // InternalD4MQuery.g:384:7: lv_values_3_1= RULE_STRING
            	            {
            	            lv_values_3_1=(Token)match(input,RULE_STRING,FOLLOW_8); 

            	            							newLeafNode(lv_values_3_1, grammarAccess.getListExprAccess().getValuesSTRINGTerminalRuleCall_2_1_0_0());
            	            						

            	            							if (current==null) {
            	            								current = createModelElement(grammarAccess.getListExprRule());
            	            							}
            	            							addWithLastConsumed(
            	            								current,
            	            								"values",
            	            								lv_values_3_1,
            	            								"org.eclipse.xtext.common.Terminals.STRING");
            	            						

            	            }
            	            break;
            	        case 2 :
            	            // InternalD4MQuery.g:399:7: lv_values_3_2= RULE_ID
            	            {
            	            lv_values_3_2=(Token)match(input,RULE_ID,FOLLOW_8); 

            	            							newLeafNode(lv_values_3_2, grammarAccess.getListExprAccess().getValuesIDTerminalRuleCall_2_1_0_1());
            	            						

            	            							if (current==null) {
            	            								current = createModelElement(grammarAccess.getListExprRule());
            	            							}
            	            							addWithLastConsumed(
            	            								current,
            	            								"values",
            	            								lv_values_3_2,
            	            								"d4m.acc.query.D4MQuery.ID");
            	            						

            	            }
            	            break;

            	    }


            	    }


            	    }


            	    }
            	    break;

            	default :
            	    break loop4;
                }
            } while (true);

            otherlv_4=(Token)match(input,15,FOLLOW_2); 

            			newLeafNode(otherlv_4, grammarAccess.getListExprAccess().getRightSquareBracketKeyword_3());
            		

            }


            }


            	leaveRule();

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "ruleListExpr"


    // $ANTLR start "entryRuleStartsWithExpr"
    // InternalD4MQuery.g:425:1: entryRuleStartsWithExpr returns [EObject current=null] : iv_ruleStartsWithExpr= ruleStartsWithExpr EOF ;
    public final EObject entryRuleStartsWithExpr() throws RecognitionException {
        EObject current = null;

        EObject iv_ruleStartsWithExpr = null;


        try {
            // InternalD4MQuery.g:425:55: (iv_ruleStartsWithExpr= ruleStartsWithExpr EOF )
            // InternalD4MQuery.g:426:2: iv_ruleStartsWithExpr= ruleStartsWithExpr EOF
            {
             newCompositeNode(grammarAccess.getStartsWithExprRule()); 
            pushFollow(FOLLOW_1);
            iv_ruleStartsWithExpr=ruleStartsWithExpr();

            state._fsp--;

             current =iv_ruleStartsWithExpr; 
            match(input,EOF,FOLLOW_2); 

            }

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "entryRuleStartsWithExpr"


    // $ANTLR start "ruleStartsWithExpr"
    // InternalD4MQuery.g:432:1: ruleStartsWithExpr returns [EObject current=null] : (otherlv_0= 'StartsWith' otherlv_1= '(' ( ( (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID ) ) ) otherlv_3= ')' ) ;
    public final EObject ruleStartsWithExpr() throws RecognitionException {
        EObject current = null;

        Token otherlv_0=null;
        Token otherlv_1=null;
        Token lv_prefix_2_1=null;
        Token lv_prefix_2_2=null;
        Token otherlv_3=null;


        	enterRule();

        try {
            // InternalD4MQuery.g:438:2: ( (otherlv_0= 'StartsWith' otherlv_1= '(' ( ( (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID ) ) ) otherlv_3= ')' ) )
            // InternalD4MQuery.g:439:2: (otherlv_0= 'StartsWith' otherlv_1= '(' ( ( (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID ) ) ) otherlv_3= ')' )
            {
            // InternalD4MQuery.g:439:2: (otherlv_0= 'StartsWith' otherlv_1= '(' ( ( (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID ) ) ) otherlv_3= ')' )
            // InternalD4MQuery.g:440:3: otherlv_0= 'StartsWith' otherlv_1= '(' ( ( (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID ) ) ) otherlv_3= ')'
            {
            otherlv_0=(Token)match(input,16,FOLLOW_9); 

            			newLeafNode(otherlv_0, grammarAccess.getStartsWithExprAccess().getStartsWithKeyword_0());
            		
            otherlv_1=(Token)match(input,17,FOLLOW_7); 

            			newLeafNode(otherlv_1, grammarAccess.getStartsWithExprAccess().getLeftParenthesisKeyword_1());
            		
            // InternalD4MQuery.g:448:3: ( ( (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID ) ) )
            // InternalD4MQuery.g:449:4: ( (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID ) )
            {
            // InternalD4MQuery.g:449:4: ( (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID ) )
            // InternalD4MQuery.g:450:5: (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID )
            {
            // InternalD4MQuery.g:450:5: (lv_prefix_2_1= RULE_STRING | lv_prefix_2_2= RULE_ID )
            int alt5=2;
            int LA5_0 = input.LA(1);

            if ( (LA5_0==RULE_STRING) ) {
                alt5=1;
            }
            else if ( (LA5_0==RULE_ID) ) {
                alt5=2;
            }
            else {
                NoViableAltException nvae =
                    new NoViableAltException("", 5, 0, input);

                throw nvae;
            }
            switch (alt5) {
                case 1 :
                    // InternalD4MQuery.g:451:6: lv_prefix_2_1= RULE_STRING
                    {
                    lv_prefix_2_1=(Token)match(input,RULE_STRING,FOLLOW_10); 

                    						newLeafNode(lv_prefix_2_1, grammarAccess.getStartsWithExprAccess().getPrefixSTRINGTerminalRuleCall_2_0_0());
                    					

                    						if (current==null) {
                    							current = createModelElement(grammarAccess.getStartsWithExprRule());
                    						}
                    						setWithLastConsumed(
                    							current,
                    							"prefix",
                    							lv_prefix_2_1,
                    							"org.eclipse.xtext.common.Terminals.STRING");
                    					

                    }
                    break;
                case 2 :
                    // InternalD4MQuery.g:466:6: lv_prefix_2_2= RULE_ID
                    {
                    lv_prefix_2_2=(Token)match(input,RULE_ID,FOLLOW_10); 

                    						newLeafNode(lv_prefix_2_2, grammarAccess.getStartsWithExprAccess().getPrefixIDTerminalRuleCall_2_0_1());
                    					

                    						if (current==null) {
                    							current = createModelElement(grammarAccess.getStartsWithExprRule());
                    						}
                    						setWithLastConsumed(
                    							current,
                    							"prefix",
                    							lv_prefix_2_2,
                    							"d4m.acc.query.D4MQuery.ID");
                    					

                    }
                    break;

            }


            }


            }

            otherlv_3=(Token)match(input,18,FOLLOW_2); 

            			newLeafNode(otherlv_3, grammarAccess.getStartsWithExprAccess().getRightParenthesisKeyword_3());
            		

            }


            }


            	leaveRule();

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "ruleStartsWithExpr"


    // $ANTLR start "entryRuleRegexExpr"
    // InternalD4MQuery.g:491:1: entryRuleRegexExpr returns [EObject current=null] : iv_ruleRegexExpr= ruleRegexExpr EOF ;
    public final EObject entryRuleRegexExpr() throws RecognitionException {
        EObject current = null;

        EObject iv_ruleRegexExpr = null;


        try {
            // InternalD4MQuery.g:491:50: (iv_ruleRegexExpr= ruleRegexExpr EOF )
            // InternalD4MQuery.g:492:2: iv_ruleRegexExpr= ruleRegexExpr EOF
            {
             newCompositeNode(grammarAccess.getRegexExprRule()); 
            pushFollow(FOLLOW_1);
            iv_ruleRegexExpr=ruleRegexExpr();

            state._fsp--;

             current =iv_ruleRegexExpr; 
            match(input,EOF,FOLLOW_2); 

            }

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "entryRuleRegexExpr"


    // $ANTLR start "ruleRegexExpr"
    // InternalD4MQuery.g:498:1: ruleRegexExpr returns [EObject current=null] : (otherlv_0= 'Regex' otherlv_1= '(' ( ( (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID ) ) ) otherlv_3= ')' ) ;
    public final EObject ruleRegexExpr() throws RecognitionException {
        EObject current = null;

        Token otherlv_0=null;
        Token otherlv_1=null;
        Token lv_pattern_2_1=null;
        Token lv_pattern_2_2=null;
        Token otherlv_3=null;


        	enterRule();

        try {
            // InternalD4MQuery.g:504:2: ( (otherlv_0= 'Regex' otherlv_1= '(' ( ( (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID ) ) ) otherlv_3= ')' ) )
            // InternalD4MQuery.g:505:2: (otherlv_0= 'Regex' otherlv_1= '(' ( ( (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID ) ) ) otherlv_3= ')' )
            {
            // InternalD4MQuery.g:505:2: (otherlv_0= 'Regex' otherlv_1= '(' ( ( (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID ) ) ) otherlv_3= ')' )
            // InternalD4MQuery.g:506:3: otherlv_0= 'Regex' otherlv_1= '(' ( ( (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID ) ) ) otherlv_3= ')'
            {
            otherlv_0=(Token)match(input,19,FOLLOW_9); 

            			newLeafNode(otherlv_0, grammarAccess.getRegexExprAccess().getRegexKeyword_0());
            		
            otherlv_1=(Token)match(input,17,FOLLOW_7); 

            			newLeafNode(otherlv_1, grammarAccess.getRegexExprAccess().getLeftParenthesisKeyword_1());
            		
            // InternalD4MQuery.g:514:3: ( ( (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID ) ) )
            // InternalD4MQuery.g:515:4: ( (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID ) )
            {
            // InternalD4MQuery.g:515:4: ( (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID ) )
            // InternalD4MQuery.g:516:5: (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID )
            {
            // InternalD4MQuery.g:516:5: (lv_pattern_2_1= RULE_STRING | lv_pattern_2_2= RULE_ID )
            int alt6=2;
            int LA6_0 = input.LA(1);

            if ( (LA6_0==RULE_STRING) ) {
                alt6=1;
            }
            else if ( (LA6_0==RULE_ID) ) {
                alt6=2;
            }
            else {
                NoViableAltException nvae =
                    new NoViableAltException("", 6, 0, input);

                throw nvae;
            }
            switch (alt6) {
                case 1 :
                    // InternalD4MQuery.g:517:6: lv_pattern_2_1= RULE_STRING
                    {
                    lv_pattern_2_1=(Token)match(input,RULE_STRING,FOLLOW_10); 

                    						newLeafNode(lv_pattern_2_1, grammarAccess.getRegexExprAccess().getPatternSTRINGTerminalRuleCall_2_0_0());
                    					

                    						if (current==null) {
                    							current = createModelElement(grammarAccess.getRegexExprRule());
                    						}
                    						setWithLastConsumed(
                    							current,
                    							"pattern",
                    							lv_pattern_2_1,
                    							"org.eclipse.xtext.common.Terminals.STRING");
                    					

                    }
                    break;
                case 2 :
                    // InternalD4MQuery.g:532:6: lv_pattern_2_2= RULE_ID
                    {
                    lv_pattern_2_2=(Token)match(input,RULE_ID,FOLLOW_10); 

                    						newLeafNode(lv_pattern_2_2, grammarAccess.getRegexExprAccess().getPatternIDTerminalRuleCall_2_0_1());
                    					

                    						if (current==null) {
                    							current = createModelElement(grammarAccess.getRegexExprRule());
                    						}
                    						setWithLastConsumed(
                    							current,
                    							"pattern",
                    							lv_pattern_2_2,
                    							"d4m.acc.query.D4MQuery.ID");
                    					

                    }
                    break;

            }


            }


            }

            otherlv_3=(Token)match(input,18,FOLLOW_2); 

            			newLeafNode(otherlv_3, grammarAccess.getRegexExprAccess().getRightParenthesisKeyword_3());
            		

            }


            }


            	leaveRule();

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "ruleRegexExpr"


    // $ANTLR start "entryRuleLiteralExpr"
    // InternalD4MQuery.g:557:1: entryRuleLiteralExpr returns [EObject current=null] : iv_ruleLiteralExpr= ruleLiteralExpr EOF ;
    public final EObject entryRuleLiteralExpr() throws RecognitionException {
        EObject current = null;

        EObject iv_ruleLiteralExpr = null;


        try {
            // InternalD4MQuery.g:557:52: (iv_ruleLiteralExpr= ruleLiteralExpr EOF )
            // InternalD4MQuery.g:558:2: iv_ruleLiteralExpr= ruleLiteralExpr EOF
            {
             newCompositeNode(grammarAccess.getLiteralExprRule()); 
            pushFollow(FOLLOW_1);
            iv_ruleLiteralExpr=ruleLiteralExpr();

            state._fsp--;

             current =iv_ruleLiteralExpr; 
            match(input,EOF,FOLLOW_2); 

            }

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "entryRuleLiteralExpr"


    // $ANTLR start "ruleLiteralExpr"
    // InternalD4MQuery.g:564:1: ruleLiteralExpr returns [EObject current=null] : ( ( (lv_value_0_1= RULE_STRING | lv_value_0_2= RULE_ID ) ) ) ;
    public final EObject ruleLiteralExpr() throws RecognitionException {
        EObject current = null;

        Token lv_value_0_1=null;
        Token lv_value_0_2=null;


        	enterRule();

        try {
            // InternalD4MQuery.g:570:2: ( ( ( (lv_value_0_1= RULE_STRING | lv_value_0_2= RULE_ID ) ) ) )
            // InternalD4MQuery.g:571:2: ( ( (lv_value_0_1= RULE_STRING | lv_value_0_2= RULE_ID ) ) )
            {
            // InternalD4MQuery.g:571:2: ( ( (lv_value_0_1= RULE_STRING | lv_value_0_2= RULE_ID ) ) )
            // InternalD4MQuery.g:572:3: ( (lv_value_0_1= RULE_STRING | lv_value_0_2= RULE_ID ) )
            {
            // InternalD4MQuery.g:572:3: ( (lv_value_0_1= RULE_STRING | lv_value_0_2= RULE_ID ) )
            // InternalD4MQuery.g:573:4: (lv_value_0_1= RULE_STRING | lv_value_0_2= RULE_ID )
            {
            // InternalD4MQuery.g:573:4: (lv_value_0_1= RULE_STRING | lv_value_0_2= RULE_ID )
            int alt7=2;
            int LA7_0 = input.LA(1);

            if ( (LA7_0==RULE_STRING) ) {
                alt7=1;
            }
            else if ( (LA7_0==RULE_ID) ) {
                alt7=2;
            }
            else {
                NoViableAltException nvae =
                    new NoViableAltException("", 7, 0, input);

                throw nvae;
            }
            switch (alt7) {
                case 1 :
                    // InternalD4MQuery.g:574:5: lv_value_0_1= RULE_STRING
                    {
                    lv_value_0_1=(Token)match(input,RULE_STRING,FOLLOW_2); 

                    					newLeafNode(lv_value_0_1, grammarAccess.getLiteralExprAccess().getValueSTRINGTerminalRuleCall_0_0());
                    				

                    					if (current==null) {
                    						current = createModelElement(grammarAccess.getLiteralExprRule());
                    					}
                    					setWithLastConsumed(
                    						current,
                    						"value",
                    						lv_value_0_1,
                    						"org.eclipse.xtext.common.Terminals.STRING");
                    				

                    }
                    break;
                case 2 :
                    // InternalD4MQuery.g:589:5: lv_value_0_2= RULE_ID
                    {
                    lv_value_0_2=(Token)match(input,RULE_ID,FOLLOW_2); 

                    					newLeafNode(lv_value_0_2, grammarAccess.getLiteralExprAccess().getValueIDTerminalRuleCall_0_1());
                    				

                    					if (current==null) {
                    						current = createModelElement(grammarAccess.getLiteralExprRule());
                    					}
                    					setWithLastConsumed(
                    						current,
                    						"value",
                    						lv_value_0_2,
                    						"d4m.acc.query.D4MQuery.ID");
                    				

                    }
                    break;

            }


            }


            }


            }


            	leaveRule();

        }

            catch (RecognitionException re) {
                recover(input,re);
                appendSkippedTokens();
            }
        finally {
        }
        return current;
    }
    // $ANTLR end "ruleLiteralExpr"

    // Delegated rules


 

    public static final BitSet FOLLOW_1 = new BitSet(new long[]{0x0000000000000000L});
    public static final BitSet FOLLOW_2 = new BitSet(new long[]{0x0000000000000002L});
    public static final BitSet FOLLOW_3 = new BitSet(new long[]{0x0000000000000800L});
    public static final BitSet FOLLOW_4 = new BitSet(new long[]{0x0000000000095030L});
    public static final BitSet FOLLOW_5 = new BitSet(new long[]{0x0000000000002000L});
    public static final BitSet FOLLOW_6 = new BitSet(new long[]{0x0000000000000010L});
    public static final BitSet FOLLOW_7 = new BitSet(new long[]{0x0000000000000030L});
    public static final BitSet FOLLOW_8 = new BitSet(new long[]{0x0000000000008800L});
    public static final BitSet FOLLOW_9 = new BitSet(new long[]{0x0000000000020000L});
    public static final BitSet FOLLOW_10 = new BitSet(new long[]{0x0000000000040000L});

}