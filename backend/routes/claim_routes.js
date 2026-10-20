const express = require('express');
const router = express.Router();

const authenticateToken =
  require('../middleware/auth_middleware');

const {
  createClaim,
  getMyClaims,
  getAllClaims
} = require('../controllers/claim_controller');

const {
  submitSecurityAnswers,
  getSecurityAnswers,
  getSecurityQuestions
} = require('../controllers/security_answer_controller');

const {
  verifyClaim
} = require('../controllers/admin_verification_controller');

const {
  generateOtp,
  getActiveOtp,
  verifyOtp
} = require('../controllers/otp_controller');


// ----------------------------------------------------
// ALL CLAIM ROUTES REQUIRE LOGIN
// ----------------------------------------------------

router.use(authenticateToken);


// ----------------------------------------------------
// USER CLAIMS
// ----------------------------------------------------

router.post('/', createClaim);

router.get('/my', getMyClaims);


// ----------------------------------------------------
// SECURITY ANSWERS
// ----------------------------------------------------

router.get('/:claimId/security-questions', getSecurityQuestions);

router.post(
  '/:claimId/security-answers',
  submitSecurityAnswers
);

router.get(
  '/:claimId/security-answers',
  getSecurityAnswers
);


// ----------------------------------------------------
// ADMIN VERIFICATION
// ----------------------------------------------------

router.patch(
  '/:claimId/verify',
  verifyClaim
);


// ----------------------------------------------------
// ADMIN - ALL CLAIMS
// ----------------------------------------------------

router.get('/', getAllClaims);

// OTP
router.post(
  '/:claimId/otp',
  generateOtp
);

router.get(
  '/:claimId/otp',
  getActiveOtp
);

router.post(
  '/:claimId/otp/verify',
  verifyOtp
);


module.exports = router;