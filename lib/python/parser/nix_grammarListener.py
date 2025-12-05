# Generated from nix_grammar.g4 by ANTLR 4.13.2
from antlr4 import *
if "." in __name__:
    from .nix_grammarParser import nix_grammarParser
else:
    from nix_grammarParser import nix_grammarParser

# This class defines a complete listener for a parse tree produced by nix_grammarParser.
class nix_grammarListener(ParseTreeListener):

    # Enter a parse tree produced by nix_grammarParser#start.
    def enterStart(self, ctx:nix_grammarParser.StartContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#start.
    def exitStart(self, ctx:nix_grammarParser.StartContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#simple_expr.
    def enterSimple_expr(self, ctx:nix_grammarParser.Simple_exprContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#simple_expr.
    def exitSimple_expr(self, ctx:nix_grammarParser.Simple_exprContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#string_expr.
    def enterString_expr(self, ctx:nix_grammarParser.String_exprContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#string_expr.
    def exitString_expr(self, ctx:nix_grammarParser.String_exprContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#function_def.
    def enterFunction_def(self, ctx:nix_grammarParser.Function_defContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#function_def.
    def exitFunction_def(self, ctx:nix_grammarParser.Function_defContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#if_expr.
    def enterIf_expr(self, ctx:nix_grammarParser.If_exprContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#if_expr.
    def exitIf_expr(self, ctx:nix_grammarParser.If_exprContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#with_expr.
    def enterWith_expr(self, ctx:nix_grammarParser.With_exprContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#with_expr.
    def exitWith_expr(self, ctx:nix_grammarParser.With_exprContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#assert_expr.
    def enterAssert_expr(self, ctx:nix_grammarParser.Assert_exprContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#assert_expr.
    def exitAssert_expr(self, ctx:nix_grammarParser.Assert_exprContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#let_expr.
    def enterLet_expr(self, ctx:nix_grammarParser.Let_exprContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#let_expr.
    def exitLet_expr(self, ctx:nix_grammarParser.Let_exprContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#attrset.
    def enterAttrset(self, ctx:nix_grammarParser.AttrsetContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#attrset.
    def exitAttrset(self, ctx:nix_grammarParser.AttrsetContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#list.
    def enterList(self, ctx:nix_grammarParser.ListContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#list.
    def exitList(self, ctx:nix_grammarParser.ListContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#binds.
    def enterBinds(self, ctx:nix_grammarParser.BindsContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#binds.
    def exitBinds(self, ctx:nix_grammarParser.BindsContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#binding_or_inherit.
    def enterBinding_or_inherit(self, ctx:nix_grammarParser.Binding_or_inheritContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#binding_or_inherit.
    def exitBinding_or_inherit(self, ctx:nix_grammarParser.Binding_or_inheritContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#binding.
    def enterBinding(self, ctx:nix_grammarParser.BindingContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#binding.
    def exitBinding(self, ctx:nix_grammarParser.BindingContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#inherit.
    def enterInherit(self, ctx:nix_grammarParser.InheritContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#inherit.
    def exitInherit(self, ctx:nix_grammarParser.InheritContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#inherit_seq.
    def enterInherit_seq(self, ctx:nix_grammarParser.Inherit_seqContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#inherit_seq.
    def exitInherit_seq(self, ctx:nix_grammarParser.Inherit_seqContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#inherit_attr.
    def enterInherit_attr(self, ctx:nix_grammarParser.Inherit_attrContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#inherit_attr.
    def exitInherit_attr(self, ctx:nix_grammarParser.Inherit_attrContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#attrpath.
    def enterAttrpath(self, ctx:nix_grammarParser.AttrpathContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#attrpath.
    def exitAttrpath(self, ctx:nix_grammarParser.AttrpathContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#attr.
    def enterAttr(self, ctx:nix_grammarParser.AttrContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#attr.
    def exitAttr(self, ctx:nix_grammarParser.AttrContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#formal_set.
    def enterFormal_set(self, ctx:nix_grammarParser.Formal_setContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#formal_set.
    def exitFormal_set(self, ctx:nix_grammarParser.Formal_setContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#formal.
    def enterFormal(self, ctx:nix_grammarParser.FormalContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#formal.
    def exitFormal(self, ctx:nix_grammarParser.FormalContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#expr.
    def enterExpr(self, ctx:nix_grammarParser.ExprContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#expr.
    def exitExpr(self, ctx:nix_grammarParser.ExprContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#expr_function.
    def enterExpr_function(self, ctx:nix_grammarParser.Expr_functionContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#expr_function.
    def exitExpr_function(self, ctx:nix_grammarParser.Expr_functionContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#expr_if.
    def enterExpr_if(self, ctx:nix_grammarParser.Expr_ifContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#expr_if.
    def exitExpr_if(self, ctx:nix_grammarParser.Expr_ifContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#expr_op.
    def enterExpr_op(self, ctx:nix_grammarParser.Expr_opContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#expr_op.
    def exitExpr_op(self, ctx:nix_grammarParser.Expr_opContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#expr_app.
    def enterExpr_app(self, ctx:nix_grammarParser.Expr_appContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#expr_app.
    def exitExpr_app(self, ctx:nix_grammarParser.Expr_appContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#expr_select.
    def enterExpr_select(self, ctx:nix_grammarParser.Expr_selectContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#expr_select.
    def exitExpr_select(self, ctx:nix_grammarParser.Expr_selectContext):
        pass


    # Enter a parse tree produced by nix_grammarParser#lambda.
    def enterLambda(self, ctx:nix_grammarParser.LambdaContext):
        pass

    # Exit a parse tree produced by nix_grammarParser#lambda.
    def exitLambda(self, ctx:nix_grammarParser.LambdaContext):
        pass



del nix_grammarParser