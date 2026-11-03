const express=require('express');
const router=express.Router();
const authenticateToken=require('../middleware/auth_middleware');
const {getMyMatchSuggestions,getMatchById,runItemMatching}=require('../controllers/match_controller');
router.use(authenticateToken);
router.get('/my',getMyMatchSuggestions);
router.post('/items/:itemId/run',runItemMatching);
router.get('/:matchId',getMatchById);
module.exports=router;



/* const express = require('express');
const router = express.Router();

const authenticateToken =
  require('../middleware/auth_middleware');

const {
  getMyMatchSuggestions,
  getMatchById
} = require('../controllers/match_controller');

router.use(authenticateToken);

router.get(
  '/my',
  getMyMatchSuggestions
);

router.get(
  '/:matchId',
  getMatchById
);

module.exports = router; */