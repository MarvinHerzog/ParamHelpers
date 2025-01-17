#FIXME: generateDesign will NOT work if there are dependencies
# over multiple levels of params and one only states the dependency only
#  wrt to the "last" param. also see daniels unit test.
#  it works as long all dependencies are stated, we need to at least document this

#FIXME: it really makes no sense to calculate the distance for params that are NA
# when we do the design and augment it right? think about what happens here


#' @title Generates a statistical design for a parameter set.
#'
#' @description
#' The following types of columns are created:
#' \tabular{ll}{
#'  numeric(vector)   \tab  \code{numeric}  \cr
#'  integer(vector)   \tab  \code{integer}  \cr
#'  discrete(vector)  \tab  \code{factor} (names of values = levels) \cr
#'  logical(vector)   \tab  \code{logical}
#' }
#' If you want to convert these, look at \code{\link[BBmisc]{convertDataFrameCols}}.
#' Dependent parameters whose constraints are unsatisfied generate \code{NA} entries in their
#' respective columns.
#' For discrete vectors the levels and their order will be preserved, even if not all levels are present.
#'
#' Currently only lhs designs are supported.
#'
#' The algorithm currently iterates the following steps:
#' \enumerate{
#'   \item{We create a space filling design for all parameters, disregarding \code{requires},
#'     a \code{trafo} or the forbidden region.}
#'   \item{Forbidden points are removed.}
#'   \item{Parameters are trafoed (potentially, depending on the setting of argument \code{trafo});
#'     dependent parameters whose constraints are unsatisfied are set to \code{NA} entries.}
#'   \item{Duplicated design points are removed. Duplicated points are not generated in a
#'    reasonable space-filling design, but the way discrete parameters and also parameter dependencies
#'    are handled make this possible.}
#'   \item{If we removed some points, we now try to augment the design in a space-filling way
#'     and iterate.}
#' }
#'
#' Note that augmenting currently is somewhat experimental as we simply generate missing points
#' via new calls to \code{\link[lhs]{randomLHS}}, but do not add points so they are maximally
#' far away from the already present ones. The reason is that the latter is quite hard to achieve
#' with complicated dependencies and forbidden regions, if one wants to ensure that points actually
#' get added... But we are working on it.
#'
#' Note that if you have trafos attached to your params, the complete creation of the design
#' (except for the detection of invalid parameters w.r.t to their \code{requires} setting)
#' takes place on the UNTRANSFORMED scale. So this function creates, e.g., a maximin LHS
#' design on the UNTRANSFORMED scale, but not necessarily the transformed scale.
#'
#' \code{generateDesign} will NOT work if there are dependencies over multiple levels of
#' parameters and the dependency is only given with respect to the \dQuote{previous} parameter.
#' A current workaround is to state all dependencies on all parameters involved.
#' (We are working on it.)
#'
#' @template arg_gendes_n
#' @template arg_parset
#' @param fun [\code{function}]\cr
#'   Function from package lhs.
#'   Possible are: \code{\link[lhs]{maximinLHS}}, \code{\link[lhs]{randomLHS}},
#'   \code{\link[lhs]{geneticLHS}}, \code{\link[lhs]{improvedLHS}}, \code{\link[lhs]{optAugmentLHS}},
#'   \code{\link[lhs]{optimumLHS}}
#'   Default is \code{\link[lhs]{randomLHS}}.
#' @param fun.args [\code{list}]\cr
#'   List of further arguments passed to \code{fun}.
#' @template arg_trafo
#' @param augment [\code{integer(1)}]\cr
#'   Duplicated values and forbidden regions in the parameter space can lead to the design
#'   becoming smaller than \code{n}. With this option it is possible to augment the design again
#'   to size \code{n}. It is not guaranteed that this always works (to full size)
#'   and \code{augment} specifies the number of tries to augment.
#'   If the the design is of size less than \code{n} after all tries, a warning is issued
#'   and the smaller design is returned.
#'   Default is 20.
#' @template ret_gendes_df
#' @export
#' @useDynLib ParamHelpers c_generateDesign c_trafo_and_set_dep_to_na
#' @examples
#' ps = makeParamSet(
#'   makeNumericParam("x1", lower = -2, upper = 1),
#'   makeIntegerParam("x2", lower = 10, upper = 20)
#' )
#' # random latin hypercube design with 5 samples:
#' generateDesign(5, ps)
#'
#' # with trafo
#' ps = makeParamSet(
#'   makeNumericParam("x", lower = -2, upper = 1),
#'   makeNumericVectorParam("y", len = 2, lower = 0, upper = 1, trafo = function(x) x/sum(x))
#' )
#' generateDesign(10, ps, trafo = TRUE)
generateDesign = #modified generateDesign
#

#

function (n = 10L, par.set, fun, fun.args = list(), trafo = FALSE, 
          augment = 20L) 
{
  res_error = tryCatch({
    if(1==2){
      #temp je env iz debuga
      n = temp$n
      par.set = temp$par.set
      fun = temp$fun
      fun.args = temp$fun.args
      trafo = temp$trafo
      augment = temp$augment
    }
    
    n = asInt(n)
    z = ParamHelpers:::doBasicGenDesignChecks(par.set)
    lower = z$lower
    upper = z$upper
    requirePackages("lhs", why = "generateDesign", default.method = "load")
    if (missing(fun)){
      fun = lhs::randomLHS
    } else {
      assertFunction(fun)
    }
    assertList(fun.args)
    assertFlag(trafo)
    augment = asInt(augment, lower = 0L)
    pars = par.set$pars
    lens = getParamLengths(par.set)
    k = sum(lens)
    pids = getParamIds(par.set, repeated = TRUE, with.nr = TRUE)
    lower2 = setNames(rep(NA_real_, k), pids)
    lower2 = insert(lower2, lower)
    upper2 = setNames(rep(NA_real_, k), pids)
    upper2 = insert(upper2, upper)
    values = ParamHelpers:::getParamSetValues(par.set)
    types.df = getParamTypes(par.set, df.cols = TRUE)
    types.int = ParamHelpers:::convertTypesToCInts(types.df)
    types.df[types.df == "factor"] = "character"
    if (trafo) {
      trafos =   lapply(pars, function(p) p$trafo)
    } else {
      trafos = replicate(length(pars), NULL, simplify = FALSE)
    }
    par.requires = lapply(pars, function(p) p$requires)
    nmissing = n
    res = data.frame()
    des = matrix(nrow = 0, ncol = k)
    for (iter in seq_len(augment)) {
      
      if (nmissing == n) {
        newdes1 = do.call(fun, insert(list(n = nmissing, k = k), 
                                      fun.args))
        ##DEBUG
        if(1==2){
          for(i in 1:1000000){
            if(i%%1000==0){cat0(i)}
            newdes = do.call(fun, insert(list(n = nmissing, k = k),
                                         fun.args))
            if(is.list(newdes)){
              browser()
            }
          }
        }
        
      }else{
        newdes1= lhs::randomLHS(nmissing, k = k)
      }
      
      stability_iter = 1
      while(stability_iter <= 5){
        if(stability_iter > 1){
          cat0("Unstable design encountered... retrying design LHS generation. Iter = ",stability_iter)
        }
        if(is.list(newdes1)){
          cat0("Newdes je list...")
          #browser()
          og_newdes1 = newdes1
          newdes1= lhs::randomLHS(nmissing, k = k)
        } else if(!is.numeric(newdes1)){
          cat0("Newdes ni numeric...")
          #browser()
          og_newdes1 = newdes1
          newdes1= lhs::randomLHS(nmissing, k = k)
        } else {
          #vse je ok, nadaljujemo
          break
        }
        stability_iter = stability_iter + 1
        
      }
     
      
      newres1 = makeDataFrame(nmissing, k, col.types = types.df)
      tryCatch({
        newres2 = .Call(ParamHelpers:::c_generateDesign, newdes1, newres1, 
                        types.int, lower2, upper2, values)
      }, error=function(e){
        cat0("Error v prvem C callu generateDesign | ",as.character(e))
        
        readr::write_rds(x = environment(),path = "DebugGenDes3.RDS")
        readr::write_rds(x = parent.env(environment()),path = "DebugGenDes3p.RDS")
        print(newdes1)
        print(newres1)
        browser()
        stop(as.character(e))
      })
      
      colnames(newres2) = pids
      if (hasForbidden(par.set)) {
        fb = unlist(lapply(dfRowsToList(newres2, par.set = par.set), 
                           function(x) {
                             isForbidden(x, par.set = par.set)
                           }))
        newres2_temp =newres2
        newdes1_temp = newdes1
        newres2 = newres2[!fb, , drop = FALSE]
        newdes1 = newdes1[!fb, , drop = FALSE]
      } 
      tryCatch({
        newres3 = .Call(ParamHelpers:::c_trafo_and_set_dep_to_na, newres2, 
                        types.int, names(pars), lens, trafos, par.requires, 
                        new.env())
      }, error=function(e){
        cat0("Error v drugem C callu generateDesign | ",as.character(e))
        browser()
        stop(as.character(e))
      })
      
      des = rbind(des, newdes1)
      res = rbind(res, newres3)
      to.remove = duplicated(res)
      des = des[!to.remove, , drop = FALSE]
      res = res[!to.remove, , drop = FALSE]
      nmissing = n - nrow(res)
      if (nmissing == 0L) 
        break
    }
    if (nrow(res) < 25) 
      warningf("generateDesign could only produce %i points instead of %i!", 
               nrow(res), n)
    colnames(res) = pids
    res = ParamHelpers:::fixDesignFactors(res, par.set)
    attr(res, "trafo") = trafo
    return(res)
  }, error = function(e) {
    cat0(as.character(e))
    browser()
    cat0("returning trivial resultframe as design (min/min|max/max|max/min,...)...")
    res_error = expand.grid(window = c(par.set$pars$window$lower, par.set$pars$window$upper), lag = c(par.set$pars$lag$lower,par.set$pars$lag$upper))
    return(res_error)
  })
  return(res_error)
}



#trace(generateDesign, edit=T)
