// Copyright 2004, Ondra Kamenik

// Decision rule and simulation

/* The main purpose of this file is a decision rule representation which
   can run a simulation. So we define an interface for classes providing
   realizations of random shocks, and define the class
   |DecisionRule|. The latter basically takes tensor container of
   derivatives of policy rules, and adds them up with respect to
   $\sigma$. The class allows to specify the $\sigma$ different from $1$.

   In addition, we provide classes for running simulations and storing
   the results, calculating some statistics and generating IRF. The class
   |DRFixPoint| allows for calculation of the fix point of a given
   decision rule. */

#ifndef DECISION_RULE_H
#define DECISION_RULE_H

#include <matio.h>

#include "kord_exception.hh"
#include "korder.hh"
#include "normal_conjugate.hh"
#include "mersenne_twister.hh"

/* This is a general interface to a shock realizations. The interface
   has only one method returning the shock realizations at the given
   time. This method is not constant, since it may change a state of the
   object. */

class ShockRealization
{
public:
  virtual ~ShockRealization()
  = default;
  virtual void get(int n, Vector &out) = 0;
  virtual int numShocks() const = 0;
};

/* This class is an abstract interface to decision rule. Its main
   purpose is to define a common interface for simulation of a decision
   rule. We need only a simulate, evaluate, cetralized clone and output
   method. The |simulate| method simulates the rule for a given
   realization of the shocks. |eval| is a primitive evaluation (it takes
   a vector of state variables (predetermined, both and shocks) and
   returns the next period variables. Both input and output are in
   deviations from the rule's steady. |evaluate| method makes only one
   step of simulation (in terms of absolute values, not
   deviations). |centralizedClone| returns a new copy of the decision
   rule, which is centralized about provided fix-point. And finally
   |writeMat| writes the decision rule to the MAT file. */

class DecisionRule
{
public:
  enum emethod { horner, trad };
  virtual ~DecisionRule()
  = default;
  virtual TwoDMatrix *simulate(emethod em, int np, const ConstVector &ystart,
                               ShockRealization &sr) const = 0;
  virtual void eval(emethod em, Vector &out, const ConstVector &v) const = 0;
  virtual void evaluate(emethod em, Vector &out, const ConstVector &ys,
                        const ConstVector &u) const = 0;
  virtual void writeMat(mat_t *fd, const char *prefix) const = 0;
  virtual DecisionRule *centralizedClone(const Vector &fixpoint) const = 0;
  virtual const Vector&getSteady() const = 0;
  virtual int nexog() const = 0;
  virtual const PartitionY&getYPart() const = 0;
};

/* The main purpose of this class is to implement |DecisionRule|
   interface, which is a simulation. To be able to do this we have to
   know the partitioning of state vector $y$ since we will need to pick
   only predetermined part $y^*$. Also, we need to know the steady state.

   The decision rule will take the form: $$y_t-\bar
   y=\sum_{i=0}^n\left[g_{(yu)^i}\right]_{\alpha_1\ldots\alpha_i}\prod_{m=1}^i
   \left[\matrix{y^*_{t-1}-\bar y^*\cr u_t}\right]^{\alpha_m},$$ where
   the tensors $\left[g_{(yu)^i}\right]$ are tensors of the constructed
   container, and $\bar y$ is the steady state.

   If we know the fix point of the rule (conditional zero shocks)
   $\tilde y$, the rule can be transformed to so called ``centralized''
   form. This is very similar to the form above but the zero dimensional
   tensor is zero:
   $$y_t-\tilde y=\sum_{i=1}^n
   \left[\tilde g_{(yu)^i}\right]_{\alpha_1\ldots\alpha_i}\prod_{m=1}^i
   \left[\matrix{y^*_{t-1}-\tilde y^*\cr u_t}\right]^{\alpha_m}.$$
   We provide a method and a constructor to transform a rule to the centralized form.

   The class is templated, the template argument is either |KOrder::fold|
   or |KOrder::unfold|. So, there are two implementations of |DecisionRule|
   interface. */

template <int t>
class DecisionRuleImpl : public ctraits<t>::Tpol, public DecisionRule
{
protected:
  using _Tparent = typename ctraits<t>::Tpol;
  const Vector ysteady;
  const PartitionY ypart;
  const int nu;
public:
  DecisionRuleImpl(const _Tparent &pol, const PartitionY &yp, int nuu,
                   const ConstVector &ys)
    : ctraits<t>::Tpol(pol), ysteady(ys), ypart(yp), nu(nuu)
  {
  }
  DecisionRuleImpl(_Tparent &pol, const PartitionY &yp, int nuu,
                   const ConstVector &ys)
    : ctraits<t>::Tpol(0, yp.ny(), pol), ysteady(ys), ypart(yp),
    nu(nuu)
  {
  }
  DecisionRuleImpl(const _Tg &g, const PartitionY &yp, int nuu,
                   const ConstVector &ys, double sigma)
    : ctraits<t>::Tpol(yp.ny(), yp.nys()+nuu), ysteady(ys), ypart(yp), nu(nuu)
  {
    fillTensors(g, sigma);
  }
  DecisionRuleImpl(const DecisionRuleImpl<t> &dr, const ConstVector &fixpoint)
    : ctraits<t>::Tpol(dr.ypart.ny(), dr.ypart.nys()+dr.nu),
    ysteady(fixpoint), ypart(dr.ypart), nu(dr.nu)
  {
    centralize(dr);
  }
  const Vector &
  getSteady() const override
  {
    return ysteady;
  }
  TwoDMatrix *simulate(emethod em, int np, const ConstVector &ystart,
                       ShockRealization &sr) const override;
  void evaluate(emethod em, Vector &out, const ConstVector &ys,
                const ConstVector &u) const override;
  DecisionRule *centralizedClone(const Vector &fixpoint) const override;
  void writeMat(mat_t *fd, const char *prefix) const override;

  int
  nexog() const override
  {
    return nu;
  }
  const PartitionY &
  getYPart() const override
  {
    return ypart;
  }
protected:
  void fillTensors(const _Tg &g, double sigma);
  void centralize(const DecisionRuleImpl &dr);
  void eval(emethod em, Vector &out, const ConstVector &v) const override;
};

/* Here we have to fill the tensor polynomial. This involves two
   separated actions. First is to evaluate the approximation at a given
   $\sigma$, the second is to compile the tensors $[g_{{(yu)}^{i+j}}]$ from
   $[g_{y^iu^j}]$. The first action is done here, the second is done by
   method |addSubTensor| of a full symmetry tensor.

   The way how the evaluation is done is described here:

   The $q-$order approximation to the solution can be written as:

   $$
   \eqalign{
   y_t-\bar y &= \sum_{l=1}^q{1\over l!}\left[\sum_{i+j+k=l}
   \left(\matrix{l\cr i,j,k}\right)\left[g_{y^iu^j\sigma^k}\right]
   _{\alpha_1\ldots\alpha_j\beta_1\ldots\beta_j}
   \prod_{m=1}^i[y^*_{t-1}-\bar y^*]^{\alpha_m}
   \prod_{n=1}^j[u_t]^{\beta_m}\sigma^k\right]\cr
   &= \sum_{l=1}^q\left[\sum_{i+j\leq l}\left(\matrix{i+j\cr i}\right)
   \left[\sum_{k=0}^{l-i-j}{1\over l!}
   \left(\matrix{l\cr k}\right)\left[g_{y^iu^j\sigma^k}\right]\sigma^k\right]
   \prod_{m=1}^i[y^*_{t-1}-\bar y^*]^{\alpha_m}
   \prod_{n=1}^j[u_t]^{\beta_m}\sigma^k\right]
   }
   $$

   This means that for each $i+j+k=l$ we have to add
   $${1\over l!}\left(\matrix{l\cr
   k}\right)\left[g_{y^iu^j\sigma^k}\right]\cdot\sigma^k=
   {1\over (i+j)!k!}\left[g_{y^iu^j\sigma^k}\right]\cdot\sigma^k$$ to
   $g_{(yu)^{i+j}}$. In addition, note that the multiplier
   $\left(\matrix{i+j\cr i}\right)$ is applied when the fully symmetric
   tensor $[g_{(yu)^{i+j}}]$ is evaluated.

   So we go through $i+j=d=0\ldots q$ and in each loop we form the fully
   symmetric tensor $[g_{(yu)^l}]$ and insert it to the container. */

template <int t>
void
DecisionRuleImpl<t>::fillTensors(const _Tg &g, double sigma)
{
  IntSequence tns(2);
  tns[0] = ypart.nys(); tns[1] = nu;
  int dfact = 1;
  for (int d = 0; d <= g.getMaxDim(); d++, dfact *= d)
    {
      auto *g_yud = new _Ttensym(ypart.ny(), ypart.nys()+nu, d);
      g_yud->zeros();

      // fill tensor of |g_yud| of dimension |d|
      /* Here we have to fill the tensor $\left[g_{(yu)^d}\right]$. So we go
         through all pairs $(i,j)$ giving $i+j=d$, and through all $k$ from
         zero up to maximal dimension minus $d$. In this way we go through all
         symmetries of $g_{y^iu^j\sigma^k}$ which will be added to $g_{(yu)^d}$.

         Note that at the beginning, |dfact| is a factorial of |d|. We
         calculate |kfact| is equal to $k!$. As indicated in
         |@<|DecisionRuleImpl::fillTensors| code@>|, the added tensor is thus
         multiplied with ${1\over d!k!}\sigma^k$. */

      for (int i = 0; i <= d; i++)
        {
          int j = d-i;
          int kfact = 1;
          _Ttensor tmp(ypart.ny(),
                       TensorDimens(Symmetry(i, j), tns));
          tmp.zeros();
          for (int k = 0; k+d <= g.getMaxDim(); k++, kfact *= k)
            {
              Symmetry sym(i, j, 0, k);
              if (g.check(sym))
                {
                  double mult = pow(sigma, k)/dfact/kfact;
                  tmp.add(mult, *(g.get(sym)));
                }
            }
          g_yud->addSubTensor(tmp);
        }

      this->insert(g_yud);
    }
}

/* The centralization is straightforward. We suppose here that the
   object's steady state is the fix point $\tilde y$. It is clear that
   the new derivatives $\left[\tilde g_{(yu)^i}\right]$ will be equal to
   the derivatives of the original decision rule |dr| at the new steady
   state $\tilde y$. So, the new derivatives are obtained by derivating the
   given decision rule $dr$ and evaluating its polynomial at
   $$dstate=\left[\matrix{\tilde y^*-\bar y^*\cr 0}\right],$$
   where $\bar y$ is the steady state of the original rule |dr|. */

template <int t>
void
DecisionRuleImpl<t>::centralize(const DecisionRuleImpl &dr)
{
  Vector dstate(ypart.nys() + nu);
  dstate.zeros();
  Vector dstate_star(dstate, 0, ypart.nys());
  ConstVector newsteady_star(ysteady, ypart.nstat, ypart.nys());
  ConstVector oldsteady_star(dr.ysteady, ypart.nstat, ypart.nys());
  dstate_star.add(1.0, newsteady_star);
  dstate_star.add(-1.0, oldsteady_star);

  _Tpol pol(dr);
  int dfac = 1;
  for (int d = 1; d <= dr.getMaxDim(); d++, dfac *= d)
    {
      pol.derivative(d-1);
      _Ttensym *der = pol.evalPartially(d, dstate);
      der->mult(1.0/dfac);
      this->insert(der);
    }
}

/* Here we evaluate repeatedly the polynomial storing results in the
   created matrix. For exogenous shocks, we use |ShockRealization|
   class, for predetermined variables, we use |ystart| as the first
   state. The |ystart| vector is required to be all state variables
   |ypart.ny()|, although only the predetermined part of |ystart| is
   used.

   We simulate in terms of $\Delta y$, this is, at the beginning the
   |ysteady| is canceled from |ystart|, we simulate, and at the end
   |ysteady| is added to all columns of the result. */

template <int t>
TwoDMatrix *
DecisionRuleImpl<t>::simulate(emethod em, int np, const ConstVector &ystart,
                              ShockRealization &sr) const
{
  KORD_RAISE_IF(ysteady.length() != ystart.length(),
                "Start and steady lengths differ in DecisionRuleImpl::simulate");
  auto *res = new TwoDMatrix(ypart.ny(), np);

  // initialize vectors and subvectors for simulation
  /* Here allocate the stack vector $(\Delta y^*, u)$, define the
     subvectors |dy|, and |u|, then we pickup predetermined parts of
     |ystart| and |ysteady|. */
  Vector dyu(ypart.nys()+nu);
  ConstVector ystart_pred(ystart, ypart.nstat, ypart.nys());
  ConstVector ysteady_pred(ysteady, ypart.nstat, ypart.nys());
  Vector dy(dyu, 0, ypart.nys());
  Vector u(dyu, ypart.nys(), nu);

  // perform the first step of simulation
  /* We cancel |ysteady| from |ystart|, get realization to |u|, and
     evaluate the polynomial. */
  dy = ystart_pred;
  dy.add(-1.0, ysteady_pred);
  sr.get(0, u);
  Vector out{res->getCol(0)};
  eval(em, out, dyu);

  // perform all other steps of simulations
  /* Also clear. If the result at some period is not finite, we pad the
     rest of the matrix with zeros. */
  int i = 1;
  while (i < np)
    {
      ConstVector ym{res->getCol(i-1)};
      ConstVector dym(ym, ypart.nstat, ypart.nys());
      dy = dym;
      sr.get(i, u);
      Vector out{res->getCol(i)};
      eval(em, out, dyu);
      if (!out.isFinite())
        {
          if (i+1 < np)
            {
              TwoDMatrix rest(*res, i+1, np-i-1);
              rest.zeros();
            }
          break;
        }
      i++;
    }

  // add the steady state to columns of |res|
  /* Even clearer. We add the steady state to the numbers computed above
     and leave the padded columns to zero. */
  for (int j = 0; j < i; j++)
    {
      Vector col{res->getCol(j)};
      col.add(1.0, ysteady);
    }

  return res;
}

/* This is one period evaluation of the decision rule. The simulation
   is a sequence of repeated one period evaluations with a difference,
   that the steady state (fix point) is cancelled and added once. Hence
   we have two special methods. */

template <int t>
void
DecisionRuleImpl<t>::evaluate(emethod em, Vector &out, const ConstVector &ys,
                              const ConstVector &u) const
{
  KORD_RAISE_IF(ys.length() != ypart.nys() || u.length() != nu,
                "Wrong dimensions of input vectors in DecisionRuleImpl::evaluate");
  KORD_RAISE_IF(out.length() != ypart.ny(),
                "Wrong dimension of output vector in DecisionRuleImpl::evaluate");
  ConstVector ysteady_pred(ysteady, ypart.nstat, ypart.nys());
  Vector ys_u(ypart.nys()+nu);
  Vector ys_u1(ys_u, 0, ypart.nys());
  ys_u1 = ys;
  ys_u1.add(-1.0, ysteady_pred);
  Vector ys_u2(ys_u, ypart.nys(), nu);
  ys_u2 = u;
  eval(em, out, ys_u);
  out.add(1.0, ysteady);
}

/* This is easy. We just return the newly created copy using the
   centralized constructor. */

template <int t>
DecisionRule *
DecisionRuleImpl<t>::centralizedClone(const Vector &fixpoint) const
{
  return new DecisionRuleImpl<t>(*this, fixpoint);
}

/* Here we only encapsulate two implementations to one, deciding
   according to the parameter. */

template <int t>
void
DecisionRuleImpl<t>::eval(emethod em, Vector &out, const ConstVector &v) const
{
  if (em == DecisionRule::horner)
    _Tparent::evalHorner(out, v);
  else
    _Tparent::evalTrad(out, v);
}

/* Write the decision rule and steady state to the MAT file. */

template <int t>
void
DecisionRuleImpl<t>::writeMat(mat_t *fd, const char *prefix) const
{
  ctraits<t>::Tpol::writeMat(fd, prefix);
  TwoDMatrix dum(ysteady.length(), 1);
  dum.getData() = ysteady;
  char tmp[100];
  sprintf(tmp, "%s_ss", prefix);
  ConstTwoDMatrix(dum).writeMat(fd, tmp);
}

/* This is exactly the same as |DecisionRuleImpl<KOrder::fold>|. The
   only difference is that we have a conversion from
   |UnfoldDecisionRule|, which is exactly
   |DecisionRuleImpl<KOrder::unfold>|. */

class UnfoldDecisionRule;
class FoldDecisionRule : public DecisionRuleImpl<KOrder::fold>
{
  friend class UnfoldDecisionRule;
public:
  FoldDecisionRule(const ctraits<KOrder::fold>::Tpol &pol, const PartitionY &yp, int nuu,
                   const ConstVector &ys)
    : DecisionRuleImpl<KOrder::fold>(pol, yp, nuu, ys)
  {
  }
  FoldDecisionRule(ctraits<KOrder::fold>::Tpol &pol, const PartitionY &yp, int nuu,
                   const ConstVector &ys)
    : DecisionRuleImpl<KOrder::fold>(pol, yp, nuu, ys)
  {
  }
  FoldDecisionRule(const ctraits<KOrder::fold>::Tg &g, const PartitionY &yp, int nuu,
                   const ConstVector &ys, double sigma)
    : DecisionRuleImpl<KOrder::fold>(g, yp, nuu, ys, sigma)
  {
  }
  FoldDecisionRule(const DecisionRuleImpl<KOrder::fold> &dr, const ConstVector &fixpoint)
    : DecisionRuleImpl<KOrder::fold>(dr, fixpoint)
  {
  }
  FoldDecisionRule(const UnfoldDecisionRule &udr);
};

/* This is exactly the same as |DecisionRuleImpl<KOrder::unfold>|, but
   with a conversion from |FoldDecisionRule|, which is exactly
   |DecisionRuleImpl<KOrder::fold>|. */

class UnfoldDecisionRule : public DecisionRuleImpl<KOrder::unfold>
{
  friend class FoldDecisionRule;
public:
  UnfoldDecisionRule(const ctraits<KOrder::unfold>::Tpol &pol, const PartitionY &yp, int nuu,
                     const ConstVector &ys)
    : DecisionRuleImpl<KOrder::unfold>(pol, yp, nuu, ys)
  {
  }
  UnfoldDecisionRule(ctraits<KOrder::unfold>::Tpol &pol, const PartitionY &yp, int nuu,
                     const ConstVector &ys)
    : DecisionRuleImpl<KOrder::unfold>(pol, yp, nuu, ys)
  {
  }
  UnfoldDecisionRule(const ctraits<KOrder::unfold>::Tg &g, const PartitionY &yp, int nuu,
                     const ConstVector &ys, double sigma)
    : DecisionRuleImpl<KOrder::unfold>(g, yp, nuu, ys, sigma)
  {
  }
  UnfoldDecisionRule(const DecisionRuleImpl<KOrder::unfold> &dr, const ConstVector &fixpoint)
    : DecisionRuleImpl<KOrder::unfold>(dr, fixpoint)
  {
  }
  UnfoldDecisionRule(const FoldDecisionRule &udr);
};

/* This class serves for calculation of the fix point of the decision
   rule given that the shocks are zero. The class is very similar to the
   |DecisionRuleImpl|. Besides the calculation of the fix point, the only
   difference between |DRFixPoint| and |DecisionRuleImpl| is that the
   derivatives wrt. shocks are ignored (since shocks are zero during the
   calculations). That is why have a different |fillTensor| method.

   The solution algorithm is Newton and is described in
   |@<|DRFixPoint::solveNewton| code@>|. It solves $F(y)=0$, where
   $F=g(y,0)-y$. The function $F$ is given by its derivatives |bigf|. The
   Jacobian of the solved system is given by derivatives stored in
   |bigfder|. */

template <int t>
class DRFixPoint : public ctraits<t>::Tpol
{
  using _Tparent = typename ctraits<t>::Tpol;
  static int max_iter;
  static int max_newton_iter;
  static int newton_pause;
  static double tol;
  const Vector ysteady;
  const PartitionY ypart;
  _Tparent *bigf;
  _Tparent *bigfder;
public:
  using emethod = typename DecisionRule::emethod;
  DRFixPoint(const _Tg &g, const PartitionY &yp,
             const Vector &ys, double sigma);
  
  ~DRFixPoint() override;

  bool calcFixPoint(emethod em, Vector &out);

  int
  getNumIter() const
  {
    return iter;
  }
  int
  getNewtonLastIter() const
  {
    return newton_iter_last;
  }
  int
  getNewtonTotalIter() const
  {
    return newton_iter_total;
  }
protected:
  void fillTensors(const _Tg &g, double sigma);
  bool solveNewton(Vector &y);
private:
  int iter;
  int newton_iter_last;
  int newton_iter_total;
};

/* Here we have to setup the function $F=g(y,0)-y$ and ${\partial
   F\over\partial y}$. The former is taken from the given derivatives of
   $g$ where a unit matrix is subtracted from the first derivative
   (|Symmetry(1)|). Then the derivative of the $F$ polynomial is
   calculated. */

template <int t>
DRFixPoint<t>::DRFixPoint(const _Tg &g, const PartitionY &yp,
                          const Vector &ys, double sigma)
  : ctraits<t>::Tpol(yp.ny(), yp.nys()),
  ysteady(ys), ypart(yp), bigf(nullptr), bigfder(nullptr)
{
  fillTensors(g, sigma);
  _Tparent yspol(ypart.nstat, ypart.nys(), *this);
  bigf = new _Tparent((const _Tparent &) yspol);
  _Ttensym *frst = bigf->get(Symmetry(1));
  for (int i = 0; i < ypart.nys(); i++)
    frst->get(i, i) = frst->get(i, i) - 1;
  bigfder = new _Tparent(*bigf, 0);
}

template <int t>
DRFixPoint<t>::~DRFixPoint()
{
  if (bigf)
    delete bigf;
  if (bigfder)
    delete bigfder;
}

/* Here we fill the tensors for the |DRFixPoint| class. We ignore the
   derivatives $g_{y^iu^j\sigma^k}$ for which $j>0$. So we go through all
   dimensions |d|, and all |k| such that |d+k| is between the maximum
   dimension and |d|, and add ${\sigma^k\over d!k!}g_{y^d\sigma^k}$ to
   the tensor $g_{(y)^d}$. */

template <int t>
void
DRFixPoint<t>::fillTensors(const _Tg &g, double sigma)
{
  int dfact = 1;
  for (int d = 0; d <= g.getMaxDim(); d++, dfact *= d)
    {
      auto *g_yd = new _Ttensym(ypart.ny(), ypart.nys(), d);
      g_yd->zeros();
      int kfact = 1;
      for (int k = 0; d+k <= g.getMaxDim(); k++, kfact *= k)
        {
          if (g.check(Symmetry(d, 0, 0, k)))
            {
              const _Ttensor *ten = g.get(Symmetry(d, 0, 0, k));
              double mult = pow(sigma, k)/dfact/kfact;
              g_yd->add(mult, *ten);
            }
        }
      this->insert(g_yd);
    }
}

/* This tries to solve polynomial equation $F(y)=0$, where $F$
   polynomial is |bigf| and its derivative is in |bigfder|. It returns
   true if the Newton converged. The method takes the given vector as
   initial guess, and rewrites it with a solution. The method guarantees
   to return the vector, which has smaller norm of the residual. That is
   why the input/output vector |y| is always changed.

   The method proceeds with a Newton step, if the Newton step improves
   the residual error. So we track residual errors in |flastnorm| and
   |fnorm| (former and current). In addition, at each step we search for
   an underrelaxation parameter |urelax|, which improves the residual. If
   |urelax| is less that |urelax_threshold|, we stop searching and stop
   the Newton. */

template <int t>
bool
DRFixPoint<t>::solveNewton(Vector &y)
{
  const double urelax_threshold = 1.e-5;
  Vector sol((const Vector &)y);
  Vector delta(y.length());
  newton_iter_last = 0;
  bool delta_finite = true;
  double flastnorm = 0.0;
  double fnorm = 0.0;
  bool converged = false;
  double urelax = 1.0;

  do
    {
      _Ttensym *jacob = bigfder->evalPartially(1, sol);
      bigf->evalHorner(delta, sol);
      if (newton_iter_last == 0)
        flastnorm = delta.getNorm();
      delta_finite = delta.isFinite();
      if (delta_finite)
        {
          ConstTwoDMatrix(*jacob).multInvLeft(delta);

          // find |urelax| improving residual
          /* Here we find the |urelax|. We cycle as long as the new residual size
             |fnorm| is greater than last residual size |flastnorm|. If the urelax
             is less than |urelax_threshold| we give up. The |urelax| is damped by
             the ratio of |flastnorm| and |fnorm|. It the ratio is close to one, we
             damp by one half. */
          bool urelax_found = false;
          urelax = 1.0;
          while (!urelax_found && urelax > urelax_threshold)
            {
              Vector soltmp((const Vector &)sol);
              soltmp.add(-urelax, delta);
              Vector f(sol.length());
              bigf->evalHorner(f, soltmp);
              fnorm = f.getNorm();
              if (fnorm <= flastnorm)
                urelax_found = true;
              else
                urelax *= std::min(0.5, flastnorm/fnorm);
            }

          sol.add(-urelax, delta);
          delta_finite = delta.isFinite();
        }
      delete jacob;
      newton_iter_last++;
      converged = delta_finite && fnorm < tol;
      flastnorm = fnorm;
    }
  while (!converged && newton_iter_last < max_newton_iter
         &&urelax > urelax_threshold);

  newton_iter_total += newton_iter_last;
  if (!converged)
    newton_iter_last = 0;
  y = (const Vector &) sol;
  return converged;
}

/* This method solves the fix point of the no-shocks rule
   $y_{t+1}=f(y_t)$. It combines dull steps with Newton attempts. The
   dull steps correspond to evaluations setting $y_{t+1}=f(y_t)$. For
   reasonable models the dull steps converge to the fix-point but very
   slowly. That is why we make Newton attempt from time to time. The
   frequency of the Newton attempts is given by |newton_pause|. We
   perform the calculations in deviations from the steady state. So, at
   the end, we have to add the steady state.

   The method also sets the members |iter|, |newton_iter_last| and
   |newton_iter_total|. These numbers can be examined later.

   The |out| vector is not touched if the algorithm has not convered. */

template <int t>
bool
DRFixPoint<t>::calcFixPoint(emethod em, Vector &out)
{
  KORD_RAISE_IF(out.length() != ypart.ny(),
                "Wrong length of out in DRFixPoint::calcFixPoint");

  Vector delta(ypart.nys());
  Vector ystar(ypart.nys());
  ystar.zeros();

  iter = 0;
  newton_iter_last = 0;
  newton_iter_total = 0;
  bool converged = false;
  do
    {
      if ((iter/newton_pause)*newton_pause == iter)
        converged = solveNewton(ystar);
      if (!converged)
        {
          bigf->evalHorner(delta, ystar);
          KORD_RAISE_IF_X(!delta.isFinite(),
                          "NaN or Inf asserted in DRFixPoint::calcFixPoint",
                          KORD_FP_NOT_FINITE);
          ystar.add(1.0, delta);
          converged = delta.getNorm() < tol;
        }
      iter++;
    }
  while (iter < max_iter && !converged);

  if (converged)
    {
      _Tparent::evalHorner(out, ystar);
      out.add(1.0, ysteady);
    }

  return converged;
}

/* This is a basically a number of matrices of the same dimensions,
   which can be obtained as simulation results from a given decision rule
   and shock realizations. We also store the realizations of shocks. */

class ExplicitShockRealization;
class SimResults
{
protected:
  int num_y;
  int num_per;
  int num_burn;
  vector<TwoDMatrix *> data;
  vector<ExplicitShockRealization *> shocks;
public:
  SimResults(int ny, int nper, int nburn = 0)
    : num_y(ny), num_per(nper), num_burn(nburn)
  {
  }
  virtual
  ~SimResults();
  void simulate(int num_sim, const DecisionRule &dr, const Vector &start,
                const TwoDMatrix &vcov, Journal &journal);
  void simulate(int num_sim, const DecisionRule &dr, const Vector &start,
                const TwoDMatrix &vcov);
  int
  getNumPer() const
  {
    return num_per;
  }
  int
  getNumBurn() const
  {
    return num_burn;
  }
  int
  getNumSets() const
  {
    return (int) data.size();
  }
  const TwoDMatrix &
  getData(int i) const
  {
    return *(data[i]);
  }
  const ExplicitShockRealization &
  getShocks(int i) const
  {
    return *(shocks[i]);
  }
  bool addDataSet(TwoDMatrix *d, ExplicitShockRealization *sr);
  void writeMat(const char *base, const char *lname) const;
  void writeMat(mat_t *fd, const char *lname) const;
};

/* This does the same as |SimResults| plus it calculates means and
   covariances of the simulated data. */

class SimResultsStats : public SimResults
{
protected:
  Vector mean;
  TwoDMatrix vcov;
public:
  SimResultsStats(int ny, int nper, int nburn = 0)
    : SimResults(ny, nper, nburn), mean(ny), vcov(ny, ny)
  {
  }
  void simulate(int num_sim, const DecisionRule &dr, const Vector &start,
                const TwoDMatrix &vcov, Journal &journal);
  void writeMat(mat_t *fd, const char *lname) const;
protected:
  void calcMean();
  void calcVcov();
};

/* This does the similar thing as |SimResultsStats| but the statistics are
   not calculated over all periods but only within each period. Then we
   do not calculate covariances with periods but only variances. */

class SimResultsDynamicStats : public SimResults
{
protected:
  TwoDMatrix mean;
  TwoDMatrix variance;
public:
  SimResultsDynamicStats(int ny, int nper, int nburn = 0)
    : SimResults(ny, nper, nburn), mean(ny, nper), variance(ny, nper)
  {
  }
  void simulate(int num_sim, const DecisionRule &dr, const Vector &start,
                const TwoDMatrix &vcov, Journal &journal);
  void writeMat(mat_t *fd, const char *lname) const;
protected:
  void calcMean();
  void calcVariance();
};

/* This goes through control simulation results, and for each control
   it adds a given impulse to a given shock and runs a simulation. The
   control simulation is then cancelled and the result is stored. After
   that these results are averaged with variances calculated.

   The means and the variances are then written to the MAT-4 file. */

class SimulationIRFWorker;
class SimResultsIRF : public SimResults
{
  friend class SimulationIRFWorker;
protected:
  const SimResults &control;
  int ishock;
  double imp;
  TwoDMatrix means;
  TwoDMatrix variances;
public:
  SimResultsIRF(const SimResults &cntl, int ny, int nper, int i, double impulse)
    : SimResults(ny, nper, 0), control(cntl),
      ishock(i), imp(impulse),
      means(ny, nper), variances(ny, nper)
  {
  }
  void simulate(const DecisionRule &dr, Journal &journal);
  void simulate(const DecisionRule &dr);
  void writeMat(mat_t *fd, const char *lname) const;
protected:
  void calcMeans();
  void calcVariances();
};

/* This simulates and gathers all statistics from the real time
   simulations. In the |simulate| method, it runs |RTSimulationWorker|s
   which accummulate information from their own estimates. The estimation
   is done by means of |NormalConj| class, which is a conjugate family of
   densities for normal distibutions. */

class RTSimulationWorker;
class RTSimResultsStats
{
  friend class RTSimulationWorker;
protected:
  Vector mean;
  TwoDMatrix vcov;
  int num_per;
  int num_burn;
  NormalConj nc;
  int incomplete_simulations;
  int thrown_periods;
public:
  RTSimResultsStats(int ny, int nper, int nburn = 0)
    : mean(ny), vcov(ny, ny),
      num_per(nper), num_burn(nburn), nc(ny),
      incomplete_simulations(0), thrown_periods(0)
  {
  }
  void simulate(int num_sim, const DecisionRule &dr, const Vector &start,
                const TwoDMatrix &vcov, Journal &journal);
  void simulate(int num_sim, const DecisionRule &dr, const Vector &start,
                const TwoDMatrix &vcov);
  void writeMat(mat_t *fd, const char *lname);
};

/* For each shock, this simulates plus and minus impulse. The class
   maintains a vector of simulation results, each gets a particular shock
   and sign (positive/negative). The results of type |SimResultsIRF| are
   stored in a vector so that even ones are positive, odd ones are
   negative.

   The constructor takes a reference to the control simulations, which
   must be finished before the constructor is called. The control
   simulations are passed to all |SimResultsIRF|s.

   The constructor also takes the vector of indices of exogenous
   variables (|ili|) for which the IRFs are generated. The list is kept
   (as |irf_list_ind|) for other methods. */

class DynamicModel;
class IRFResults
{
  vector<SimResultsIRF *> irf_res;
  const DynamicModel &model;
  vector<int> irf_list_ind;
public:
  IRFResults(const DynamicModel &mod, const DecisionRule &dr,
             const SimResults &control, vector<int> ili,
             Journal &journal);
  ~IRFResults();
  void writeMat(mat_t *fd, const char *prefix) const;
};

/* This worker simulates the given decision rule and inserts the result
   to |SimResults|. */

class SimulationWorker : public THREAD
{
protected:
  SimResults &res;
  const DecisionRule &dr;
  DecisionRule::emethod em;
  int np;
  const Vector &st;
  ShockRealization &sr;
public:
  SimulationWorker(SimResults &sim_res,
                   const DecisionRule &dec_rule,
                   DecisionRule::emethod emet, int num_per,
                   const Vector &start, ShockRealization &shock_r)
    : res(sim_res), dr(dec_rule), em(emet), np(num_per), st(start), sr(shock_r)
  {
  }
  void operator()() override;
};

/* This worker simulates a given impulse |imp| to a given shock
   |ishock| based on a given control simulation with index |idata|. The
   control simulations are contained in |SimResultsIRF| which is passed
   to the constructor. */

class SimulationIRFWorker : public THREAD
{
  SimResultsIRF &res;
  const DecisionRule &dr;
  DecisionRule::emethod em;
  int np;
  int idata;
  int ishock;
  double imp;
public:
  SimulationIRFWorker(SimResultsIRF &sim_res,
                      const DecisionRule &dec_rule,
                      DecisionRule::emethod emet, int num_per,
                      int id, int ishck, double impulse)
    : res(sim_res), dr(dec_rule), em(emet), np(num_per),
      idata(id), ishock(ishck), imp(impulse)
  {
  }
  void operator()() override;
};

/* This class does the real time simulation job for
   |RTSimResultsStats|. It simulates the model period by period. It
   accummulates the information in the |RTSimResultsStats::nc|. If NaN or
   Inf is observed, it ends the simulation and adds to the
   |thrown_periods| of |RTSimResultsStats|. */

class RTSimulationWorker : public THREAD
{
protected:
  RTSimResultsStats &res;
  const DecisionRule &dr;
  DecisionRule::emethod em;
  int np;
  const Vector &ystart;
  ShockRealization &sr;
public:
  RTSimulationWorker(RTSimResultsStats &sim_res,
                     const DecisionRule &dec_rule,
                     DecisionRule::emethod emet, int num_per,
                     const Vector &start, ShockRealization &shock_r)
    : res(sim_res), dr(dec_rule), em(emet), np(num_per), ystart(start), sr(shock_r)
  {
  }
  void operator()() override;
};

/* This class generates draws from Gaussian distribution with zero mean
   and the given variance-covariance matrix. It stores the factor of vcov
   $V$ matrix, yielding $FF^T = V$. */

class RandomShockRealization : virtual public ShockRealization
{
protected:
  MersenneTwister mtwister;
  TwoDMatrix factor;
public:
  RandomShockRealization(const ConstTwoDMatrix &v, unsigned int iseed)
    : mtwister(iseed), factor(v.nrows(), v.nrows())
  {
    schurFactor(v);
  }
  RandomShockRealization(const RandomShockRealization &sr)
    : mtwister(sr.mtwister), factor(sr.factor)
  {
  }
  ~RandomShockRealization()
  override = default;
  void get(int n, Vector &out) override;
  int
  numShocks() const override
  {
    return factor.nrows();
  }
protected:
  void choleskyFactor(const ConstTwoDMatrix &v);
  void schurFactor(const ConstTwoDMatrix &v);
};

/* This is just a matrix of finite numbers. It can be constructed from
   any |ShockRealization| with a given number of periods. */

class ExplicitShockRealization : virtual public ShockRealization
{
  TwoDMatrix shocks;
public:
  ExplicitShockRealization(const ConstTwoDMatrix &sh)
    : shocks(sh)
  {
  }
  ExplicitShockRealization(const ExplicitShockRealization &sr)
    : shocks(sr.shocks)
  {
  }
  ExplicitShockRealization(ShockRealization &sr, int num_per);
  void get(int n, Vector &out) override;
  int
  numShocks() const override
  {
    return shocks.nrows();
  }
  const TwoDMatrix &
  getShocks()
  {
    return shocks;
  }
  void addToShock(int ishock, int iper, double val);
  void
  print() const
  {
    shocks.print();
  }
};

/* This represents a user given shock realization. The first matrix of
   the constructor is a covariance matrix of shocks, the second matrix is
   a rectangular matrix, where columns correspond to periods, rows to
   shocks. If an element of the matrix is {\tt NaN}, or {\tt Inf}, or
   {\tt -Inf}, then the random shock is taken instead of that element.

   In this way it is a generalization of both |RandomShockRealization|
   and |ExplicitShockRealization|. */

class GenShockRealization : public RandomShockRealization, public ExplicitShockRealization
{
public:
  GenShockRealization(const ConstTwoDMatrix &v, const ConstTwoDMatrix &sh, int seed)
    : RandomShockRealization(v, seed), ExplicitShockRealization(sh)
  {
    KORD_RAISE_IF(sh.nrows() != v.nrows() || v.nrows() != v.ncols(),
                  "Wrong dimension of input matrix in GenShockRealization constructor");
  }
  void get(int n, Vector &out) override;
  int
  numShocks() const override
  {
    return RandomShockRealization::numShocks();
  }
};

#endif
